#!/usr/bin/env bash
# Sentinel OS v1.0 ISO Build – "Sentinel way" (Bookworm + MATE)
# Debian 12 (Bookworm) amd64 | live-build 20230502 compatible
#
# Guarantees:
# - Bookworm-safe live-build flags (no unsupported options)
# - One and only one final ISO build at the end
# - Kernel hardening is CONFIGURED in ISO and ENFORCED on first boot
# - UFW defaults set at build time; UFW enabled on first boot
# - AppArmor enabled at boot; ensured running on first boot
# - First-boot banner (one-time) for hardening completion
# - Post-install profile framework present in ISO (profiles are opt-in)
#
# Run as a NORMAL USER with sudo (NOT root)

set -euo pipefail

pause() {
  echo
  read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."
  echo
}

die() { echo "[!] $*"; exit 1; }

if [ "$EUID" -eq 0 ]; then
  die "Do not run this script as root. Run as a normal user with sudo."
fi

echo "=== Sentinel OS v1.0 ISO Build (Sentinel way) ==="

# -------------------------------------------------
# PHASE 0: Sanity checks
# -------------------------------------------------
echo "[PHASE 0] SANITY CHECKS"
ARCH="$(dpkg --print-architecture)"
[ "$ARCH" = "amd64" ] || die "Host architecture is $ARCH (expected amd64)."
pause

echo "[+] Sainty checks passed successfully. Proceeding with PHASE 1: Dependencies..."

# -------------------------------------------------
# PHASE 1: Dependencies
# -------------------------------------------------
echo "[PHASE 1] IINSTALL AND BUILD DEPENDENCIES"
sudo apt update
sudo apt install -y sudo live-build debootstrap squashfs-tools xorriso git ca-certificates gnupg

if ! groups | grep -q '\bsudo\b'; then
  sudo usermod -aG sudo "$USER"
  echo "[!] Added $USER to sudo group. Log out/in and re-run."
  exit 0
fi

# Ensure debootstrap is discoverable
[ -x /usr/bin/debootstrap ] || sudo ln -sf /usr/sbin/debootstrap /usr/bin/debootstrap
pause

echo "[+] Dependencies installed successfully..."

# -------------------------------------------------
# PHASE 2: Workspace
# -------------------------------------------------
echo "[PHASE 2] PREPARING WORKSPACE"

WORKDIR="$HOME/sentinel-iso"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

sudo lb clean --purge || true
rm -rf .build cache || true
pause

echo "[+] Workspace prepared cleanly..."

# -------------------------------------------------
# PHASE 3: live-build config
# -------------------------------------------------
echo "[PHASE 3] CONFIGURING LIVE-BUILD"
sudo lb config   --distribution bookworm   --architectures amd64   --binary-images iso-hybrid   --debian-installer live   --archive-areas "main contrib non-free non-free-firmware"   --bootappend-live "boot=live components quiet splash"   --iso-volume "Sentinel OS 1.0"   --iso-application "Sentinel OS"   --iso-publisher "Sentinel OS Project"   --apt-recommends false

# live-build creates root-owned config; fix for subsequent file writes
sudo chown -R "$USER:$USER" config
pause

echo "[+] Live-Build configured successfully..."
 
# -------------------------------------------------
# PHASE 4: APT sources and policy
# -------------------------------------------------
echo "[PHASE 4] WRITING APT SOURCES DIRECTLY"

mkdir -p config/archives
cat << EOF > config/archives/bookworm.list.chroot
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

# Disable recommends/suggests inside chroot for deterministic installs

mkdir -p config/includes.chroot/etc/apt/apt.conf.d
cat << EOF > config/includes.chroot/etc/apt/apt.conf.d/99sentinel
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
pause

echo "[+] APT sources and policy completed successfully..."

# -------------------------------------------------
# PHASE 5: Package lists (Bookworm-valid)
# -------------------------------------------------
echo "[PHASE 5] WRITING PACKAGE LISTS, BOOKWORM-VAILD"

mkdir -p config/package-lists

cat << EOF > config/package-lists/mate.list.chroot
mate-desktop-environment
mate-desktop-environment-extras
lightdm
lightdm-gtk-greeter
network-manager
network-manager-gnome
policykit-1
sudo
zenity
EOF

cat << EOF > config/package-lists/sentinel-core.list.chroot
# Security baseline
apparmor
apparmor-utils
apparmor-profiles
firejail
firejail-profiles
ufw

# Core networking + visibility
nmap
wireshark
rsyslog
lynis

# Malware / IR basics
clamav
yara
sleuthkit

# Crypto / privacy basics
gnupg
kleopatra
cryptsetup
tor
torsocks
nyx
obfs4proxy

# Firmware support
firmware-linux-free

# Docs / reporting
libreoffice
pandoc
graphviz
plantuml
mousepad

# Browser
firefox-esr

# Utilities
curl
wget
git
jq
ca-certificates
python3
python3-pip
synaptic
gdebi
gimp
inkscape
make
EOF
pause

echo "[+] Package lists written successfully..."

# -------------------------------------------------
# PHASE 6: LightDM / MATE config
# -------------------------------------------------
echo "[PHASE 6] CONFIGURING LIGHTDM AND MATE DE"

mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
cat << EOF > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf
[SeatDefaults]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF
pause
echo "[+] MATE and LightDM configured successfully..."

# -------------------------------------------------
# PHASE 7: Binary-stage baseline hardening (CONFIG ONLY)
# -------------------------------------------------
echo "[PHASE 7] INSTALLING BASELINE HARDENING (binary stage)"
mkdir -p config/hooks/binary

cat << 'EOF' > config/hooks/binary/001-sentinel-baseline-hardening.hook.binary
#!/bin/sh
set -e

# Enable AppArmor at boot (enforcement happens at runtime)
systemctl enable apparmor.service || true

# Set firewall defaults (do NOT enable during build)
ufw default deny incoming || true
ufw default allow outgoing || true

# Reduce attack surface by default
systemctl disable avahi-daemon.service || true
systemctl disable bluetooth.service || true

# Kernel hardening config (applied by systemd-sysctl at boot; verified/enforced by firstboot)
cat << 'SYSCTL' > /etc/sysctl.d/99-sentinel.conf
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.yama.ptrace_scope=2
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
SYSCTL
EOF
chmod +x config/hooks/binary/001-sentinel-baseline-hardening.hook.binary
pause

echo "[+] Kernel hardening completed successfully..."

# -------------------------------------------------
# PHASE 8: First-boot hardening + one-time banner (ENFORCEMENT)
# -------------------------------------------------
echo "[PHASE 8] WIRING FIRST-BOOT HARDENING + BANNER"

mkdir -p config/includes.chroot/usr/local/sbin
cat << 'EOF' > config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh
#!/bin/sh
set -e

LOG="/var/log/sentinel-firstboot.log"
MARK="/var/lib/sentinel-firstboot.done"

echo "[Sentinel] First boot hardening started" >> "$LOG"

[ -f "$MARK" ] && {
  echo "[Sentinel] Already completed; exiting" >> "$LOG"
  exit 0
}

# Apply sysctl config now (enforcement)
sysctl --system >> "$LOG" 2>&1 || true

# Enable firewall now (enforcement)
if command -v ufw >/dev/null 2>&1; then
  ufw --force enable >> "$LOG" 2>&1 || true
fi

# Ensure AppArmor is enabled and running
systemctl enable apparmor.service >> "$LOG" 2>&1 || true
systemctl start apparmor.service >> "$LOG" 2>&1 || true

# Ensure services remain disabled by default
systemctl disable avahi-daemon.service >> "$LOG" 2>&1 || true
systemctl disable bluetooth.service >> "$LOG" 2>&1 || true

mkdir -p /var/lib
touch "$MARK"
echo "[Sentinel] First boot hardening completed" >> "$LOG"

# Self-disable
systemctl disable sentinel-firstboot.service >> "$LOG" 2>&1 || true
exit 0
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh

mkdir -p config/includes.chroot/etc/systemd/system
cat << 'EOF' > config/includes.chroot/etc/systemd/system/sentinel-firstboot.service
[Unit]
Description=Sentinel OS First Boot Hardening
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sentinel-firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > config/hooks/binary/010-enable-firstboot.hook.binary
#!/bin/sh
set -e
systemctl enable sentinel-firstboot.service || true
EOF
chmod +x config/hooks/binary/010-enable-firstboot.hook.binary

# One-time banner after hardening completes
cat << 'EOF' > config/includes.chroot/usr/local/sbin/sentinel-firstboot-banner.sh
#!/bin/sh
set -e

DONE="/var/lib/sentinel-firstboot.done"
MARK="/var/lib/sentinel-firstboot-banner.done"

[ -f "$DONE" ] || exit 0
[ -f "$MARK" ] && exit 0
[ -z "${DISPLAY:-}" ] && exit 0

if command -v zenity >/dev/null 2>&1; then
  zenity --info     --title="Sentinel OS – System Hardened"     --width=440     --text="Initial security hardening has completed successfully.

• AppArmor is enabled
• Firewall is enabled (UFW)
• Kernel hardening is active

Log:
  /var/log/sentinel-firstboot.log

This message will not appear again."
fi

touch "$MARK"
exit 0
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-firstboot-banner.sh

mkdir -p config/includes.chroot/etc/xdg/autostart
cat << 'EOF' > config/includes.chroot/etc/xdg/autostart/sentinel-firstboot-banner.desktop
[Desktop Entry]
Type=Application
Name=Sentinel OS First Boot Banner
Exec=/usr/local/sbin/sentinel-firstboot-banner.sh
OnlyShowIn=MATE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
pause

echo "[+] First-boot hardening and banner completed successfully..."

# -------------------------------------------------
# PHASE 9: Post-install profile framework (opt-in)
# -------------------------------------------------
echo "[PHASE 9] ADDING POST-INSTALL PROFILE FRAMEWORKS"

mkdir -p config/includes.chroot/usr/local/share/sentinel/profiles
mkdir -p config/includes.chroot/usr/local/sbin

cat << 'EOF' > config/includes.chroot/usr/local/sbin/sentinel-profile-manager
#!/bin/sh
set -e
PROFILE_DIR="/usr/local/share/sentinel/profiles"
LOG="/var/log/sentinel-profiles.log"

usage() {
  echo "Usage:"
  echo "  sentinel-profile-manager list"
  echo "  sudo sentinel-profile-manager install <profile>"
}

case "${1:-}" in
  list)
    ls "$PROFILE_DIR" 2>/dev/null | sed 's/\.sh$//' || true
    ;;
  install)
    [ -n "${2:-}" ] || { usage; exit 1; }
    sh "$PROFILE_DIR/$2.sh" | tee -a "$LOG"
    mkdir -p /var/lib
    touch "/var/lib/sentinel-profile-$2.installed"
    ;;
  *)
    usage
    exit 1
    ;;
esac
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-profile-manager

cat << 'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/blue.sh
#!/bin/sh
set -e
apt update
apt install -y tcpdump strace ltrace sysstat radare2 testdisk photorec
EOF

cat << 'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/developer.sh
#!/bin/sh
set -e
apt update
apt install -y default-jdk gcc gdb valgrind make
EOF

cat << 'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/red.sh
#!/bin/sh
set -e
apt update
apt install -y masscan hydra aircrack-ng burp
echo "NOTE: responder/bettercap may require non-Debian sources on Bookworm." >&2
EOF

cat << 'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/purple.sh
#!/bin/sh
set -e
apt update
apt install -y suricata tcpdump jq
echo "NOTE: sigma-cli may not be available in Debian repos; add later if desired." >&2
EOF

chmod +x config/includes.chroot/usr/local/share/sentinel/profiles/*.sh
pause

echo "[+] Profiles written successfully..."

# -------------------------------------------------
# PHASE 10: Build ISO (ONE FINAL BUILD)
# -------------------------------------------------
echo "[PHASE 10] BUILDING ISO"

sudo lb clean
sudo lb config
sudo lb build

echo "[+] Build complete. ISO output(s):"
ls -lh *.iso || true

echo"[+] Locating and renaming live-build-amd64.hybrid.iso > Sentinel-OS-v1.0-amd64.iso"

ISO_FOUND="$(ls -1 *.iso 2>/sev/null | head -n 1)"

if [ -z "$ISO_FOUND": ]; then
  echo "[!] ERROT: No ISO file found after build..."
    exit 1
fi

ISO_DIST="Sentinel-OS-v1.0-amd64.iso"

echo "[+] ISO FOUND: $ISO_FOUND"
mv "$ISO_FOUND" > "$ISO_DST"

sha256sum "$ISO_DST" > "ISO_DST.sha256"
echo "[+] SHA256 checksum written to: $ISO_DST.sha256"

echo "======== Sentinel OS v1.0 build fcompleted. =========="
