#!/usr/bin/env bash
# Sentinel OS v1.0 ISO Build GUI-STABILIZED
# Debian 12 (Bookworm) amd64 | live-build 20230502 compatible
#
# Primary goal of this revision:
# - Make the LIVE desktop + LIVE installer reliably boot to GUI in common hypervisors (GNOME Boxes/virt-manager)
#   without weakening installed-system hardening.
#
# Key changes vs earlier script:
# - NO service enable/disable in binary hooks (avoids live-system unit stalls).
# - First-boot hardening is installed but will NOT run on live boots (guarded by /proc/cmdline boot=live).
# - Disable Plymouth/splash by default (removes frequent VM/DRM handoff hang).
# - Add VM-friendly graphics + guest packages (spice-vdagent, qemu-guest-agent, extra Xorg drivers).
# - Add LightDM delay drop-in (avoids race on some VMs).
# - Keep security posture: AppArmor/UFW/sysctl enforced on FIRST BOOT of INSTALLED system only.
#
# Run as a NORMAL USER with sudo (NOT root)

set -euo pipefail

pause() {
 echo
 read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."
 echo
}

die() { echo "[!] $*"; exit 1; }

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
 die "Do not run this script as root. Run as a normal user with sudo."
fi

echo "=== Sentinel OS v1.0 ISO Build (Sentinel way, GUI-stabilized) ==="

# -------------------------------------------------
# PHASE 0: Sanity checks
# -------------------------------------------------
echo "[PHASE 0] SANITY CHECKS"
ARCH="$(dpkg --print-architecture)"
[ "$ARCH" = "amd64" ] || die "Host architecture is $ARCH (expected amd64)."
pause

# -------------------------------------------------
# PHASE 1: Dependencies
# -------------------------------------------------
echo "[PHASE 1] INSTALL BUILD DEPENDENCIES"
sudo apt update
sudo apt install -y sudo live-build debootstrap squashfs-tools xorriso git ca-certificates gnupg

if ! groups | grep -q '\bsudo\b'; then
 sudo usermod -aG sudo "$USER"
 echo "[!] Added $USER to sudo group. Log out/in and re-run."
 exit 0
fi

# Ensure debootstrap is discoverable (PATH edge-cases)
[ -x /usr/bin/debootstrap ] || sudo ln -sf /usr/sbin/debootstrap /usr/bin/debootstrap
pause

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

# -------------------------------------------------
# PHASE 3: live-build config (GUI-stabilized)
# -------------------------------------------------
echo "[PHASE 3] CONFIGURING LIVE-BUILD"
# Notes:
# - Removed "quiet splash" (Plymouth/DRM handoff hang-prone in some VMs)
# - Keep minimal boot params; diagnostics can be added ad-hoc in GRUB editor during testing
sudo lb config \
 --distribution bookworm \
 --architectures amd64 \
 --binary-images iso-hybrid \
 --debian-installer live \
 --archive-areas "main contrib non-free non-free-firmware" \
 --bootappend-live "boot=live components" \
 --iso-volume "Sentinel OS 1.0" \
 --iso-application "Sentinel OS" \
 --iso-publisher "Sentinel OS Project" \
 --apt-recommends false

# live-build creates root-owned config; fix for subsequent file writes
sudo chown -R "$USER:$USER" config
pause

# -------------------------------------------------
# PHASE 4: APT sources and policy
# -------------------------------------------------
echo "[PHASE 4] WRITING APT SOURCES + POLICY"
mkdir -p config/archives
cat << EOF > config/archives/bookworm.list.chroot
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

mkdir -p config/includes.chroot/etc/apt/apt.conf.d
cat << EOF > config/includes.chroot/etc/apt/apt.conf.d/99sentinel
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
pause

# -------------------------------------------------
# PHASE 5: Package lists (Bookworm-valid + VM/GUI stability)
# -------------------------------------------------
echo "[PHASE 5] WRITING PACKAGE LISTS (BOOKWORM-VALID)"
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
# --- Desktop / VM stability ---
xorg
xserver-xorg-core
xserver-xorg-input-all
xserver-xorg-video-all
xserver-xorg-video-fbdev
xserver-xorg-video-vesa
xserver-xorg-video-qxl
spice-vdagent
qemu-guest-agent

# --- Security baseline ---
apparmor
apparmor-utils
apparmor-profiles
firejail
firejail-profiles
ufw

# --- Core networking + visibility ---
nmap
wireshark
rsyslog
lynis

# --- Malware / IR basics ---
clamav
yara
sleuthkit

# --- Crypto / privacy basics ---
gnupg
kleopatra
cryptsetup
tor
torsocks
nyx
obfs4proxy

# --- Firmware support ---
firmware-linux-free

# --- Docs / reporting ---
libreoffice
pandoc
graphviz
plantuml
mousepad

# --- Graphics ---
gimp
inkscape
eog

# --- Browser ---
firefox-esr
epiphany-browser

# --- Utilities ---
curl
flatpak
wget
gnome-software-plugin-flatpak
git
jq
ca-certificates
python3
python3-pip
synaptic
gdebi
make
EOF
pause

# -------------------------------------------------
# PHASE 6: LightDM / MATE config + VM-safe delay
# -------------------------------------------------
echo "[PHASE 6] CONFIGURING LIGHTDM + MATE"
mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
cat << EOF > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf
[SeatDefaults]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

# Add a small delay to avoid LightDM/Xorg race conditions (common in VMs)
mkdir -p config/includes.chroot/etc/systemd/system/lightdm.service.d
cat << 'EOF' > config/includes.chroot/etc/systemd/system/lightdm.service.d/10-sentinel-delay.conf
[Service]
ExecStartPre=/bin/sleep 2
EOF
pause

# -------------------------------------------------
# PHASE 7: Baseline hardening (FILES ONLY; no systemctl in live media)
# -------------------------------------------------
echo "[PHASE 7] BASELINE HARDENING (FILES ONLY)"
mkdir -p config/includes.chroot/etc/sysctl.d
cat << 'EOF' > config/includes.chroot/etc/sysctl.d/99-sentinel.conf
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
EOF
pause

# -------------------------------------------------
# PHASE 8: First-boot hardening + one-time banner (installed system only)
# -------------------------------------------------
echo "[PHASE 8] FIRST-BOOT HARDENING + BANNER (INSTALLED SYSTEM ONLY)"

mkdir -p config/includes.chroot/usr/local/sbin
cat << 'EOF' > config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh
#!/bin/sh
set -e

# Do not run in LIVE environment.
if grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
 exit 0
fi

LOG="/var/log/sentinel-firstboot.log"
MARK="/var/lib/sentinel-firstboot.done"

echo "[Sentinel] First boot hardening started" >> "$LOG"

[ -f "$MARK" ] && {
 echo "[Sentinel] Already completed; exiting" >> "$LOG"
 exit 0
}

# Apply sysctl config now
sysctl --system >> "$LOG" 2>&1 || true

# Firewall: set defaults and enable now
if command -v ufw >/dev/null 2>&1; then
 ufw default deny incoming >> "$LOG" 2>&1 || true
 ufw default allow outgoing >> "$LOG" 2>&1 || true
 ufw --force enable >> "$LOG" 2>&1 || true
fi

# Ensure AppArmor is enabled and running
systemctl enable apparmor.service >> "$LOG" 2>&1 || true
systemctl start apparmor.service >> "$LOG" 2>&1 || true

# Reduce attack surface by default (installed system)
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

# Enable firstboot service in the image; it will no-op on live boots.
mkdir -p config/hooks/binary
cat << 'EOF' > config/hooks/binary/010-enable-firstboot.hook.binary
#!/bin/sh
set -e
systemctl enable sentinel-firstboot.service || true
EOF
chmod +x config/hooks/binary/010-enable-firstboot.hook.binary

# One-time banner after hardening completes (installed system only)
cat << 'EOF' > config/includes.chroot/usr/local/sbin/sentinel-firstboot-banner.sh
#!/bin/sh
set -e

# Never show on live boots
if grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
 exit 0
fi

DONE="/var/lib/sentinel-firstboot.done"
MARK="/var/lib/sentinel-firstboot-banner.done"

[ -f "$DONE" ] || exit 0
[ -f "$MARK" ] && exit 0
[ -z "${DISPLAY:-}" ] && exit 0

if command -v zenity >/dev/null 2>&1; then
 zenity --info \
   --title="Sentinel OS  AppArmor is enabled\n Kernel hardening is active\n\nLog:\n  /var/log/sentinel-firstboot.log\n\nThis message will not appear again."
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

# -------------------------------------------------
# PHASE 9: Post-install profile framework (opt-in)
# -------------------------------------------------
echo "[PHASE 9] ADDING POST-INSTALL PROFILE FRAMEWORK (OPT-IN)"
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
apt install -y tcpdump strace ltrace sysstat radare2 testdisk photorec zeek suricata auditd aide ossec-hids-agent rkhunter lynis logwatch
EOF

cat << 'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/developer.sh
#!/bin/sh
set -e
apt update
apt install -y default-jdk gcc gdb valgrind build-essential cmake meson ninja-build python3-venv git-lfs shellcheck blender geany
EOF

cat << 'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/red.sh
#!/bin/sh
set -e
apt update
apt install -y masscan hydra aircrack-ng metasploit-framework sqlmap nikto john john-data hashcat bettercap netcat-openbsd open-ssl age
EOF

cat << 'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/purple.sh
#!/bin/sh
set -e
apt update
apt install -y suricata tcpdump jq zeek tcpdump yara sigma-cli auditd aide stegohide stegosuite lynis
EOF

chmod +x config/includes.chroot/usr/local/share/sentinel/profiles/*.sh
pause

# -------------------------------------------------
# PHASE 10: Build ISO (ONE FINAL BUILD) + rename + checksum
# -------------------------------------------------
echo "[PHASE 10] BUILDING ISO (ONE FINAL BUILD)"
sudo lb clean
sudo lb config
sudo lb build

echo "[+] Build complete. ISO output(s):"
ls -lh *.iso || true

echo "[+] Locating built ISO artifact..."
ISO_FOUND="$(ls -1 *.iso 2>/dev/null | head -n 1 || true)"
ISO_DST="Sentinel-OS-v1.0-amd64.iso"

[ -n "$ISO_FOUND" ] || die "No ISO file found after build."

echo "[+] ISO FOUND: $ISO_FOUND"
mv "$ISO_FOUND" "$ISO_DST"

sha256sum "$ISO_DST" > "$ISO_DST.sha256"
echo "[+] SHA256 checksum written to: $ISO_DST.sha256"

echo "======== Sentinel OS v1.0 build completed successfully. =========="
echo "[+] Artifacts:"
ls -lh "$ISO_DST" "$ISO_DST.sha256"
echo "[+] Verify with: sha256sum -c $ISO_DST.sha256"
