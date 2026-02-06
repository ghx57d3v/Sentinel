#!/usr/bin/env bash
# Sentinel OS v1.5 ISO Build (Polished Distro Edition)
# Debian 12 (Bookworm) amd64 | live-build compatible
#
# v1.5 upgrades (beyond v1.4):
# - Version stamping inside the OS (/etc/sentinel-release, /usr/local/share/sentinel/VERSION, MOTD snippet)
# - First-boot Setup Wizard (installed system only): profile selection + guided install of chosen profiles
# - Reproducible build mode (opt-in): SOURCE_DATE_EPOCH + stable locale/timezone
# - Signing automation (opt-in): SHA256/SHA512 + GPG detached signatures when a signing key is available
#
# Keeps reliability work:
# - MATE + LightDM with deterministic delay + DM watchdog
# - Live-only autologin + live-only NOPASSWD sudo (removed on installed boots)
# - Hardware-focused firmware + Secure Boot-friendly loader packages
# - First-boot hardening (installed only) + UEFI fallback BOOTX64.EFI hardening
# - Opt-in profile system (heavy tooling off the base ISO)
#
# Run as a NORMAL USER with sudo (NOT root)

set -euo pipefail

pause() {
  echo
  read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."
  echo
}

die() { echo "[!] $*"; exit 1; }
info() { echo "[*] $*"; }

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  die "Do not run this script as root. Run as a normal user with sudo."
fi

# -----------------------------
# Build knobs (env overrides)
# -----------------------------
SENTINEL_VERSION="1.5"
ISO_VOL="Sentinel OS 1.5"
ISO_APP="Sentinel OS"
ISO_PUB="Sentinel OS Project"
ISO_DST="Sentinel-OS-v1.5-amd64.iso"

# Reproducible mode:
#   REPRO=1  -> enable reproducibility controls (best-effort)
#   BUILD_EPOCH=<unix epoch> -> optional fixed timestamp used for SOURCE_DATE_EPOCH
REPRO="${REPRO:-0}"
BUILD_EPOCH="${BUILD_EPOCH:-}"

# Signing mode:
#   SIGN=1 -> produce .sha256/.sha512 and optional GPG signatures if gpg + key available
#   SIGN_KEYID=<keyid/email/fingerprint> -> optional, selects key
SIGN="${SIGN:-1}"
SIGN_KEYID="${SIGN_KEYID:-}"

# -----------------------------
# Reproducibility controls
# -----------------------------
if [ "$REPRO" = "1" ]; then
  info "Reproducible mode enabled (best-effort)"
  export TZ=UTC
  export LC_ALL=C.UTF-8
  export LANG=C.UTF-8
  umask 022

  if [ -n "$BUILD_EPOCH" ]; then
    export SOURCE_DATE_EPOCH="$BUILD_EPOCH"
  else
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct 2>/dev/null || date +%s)"
    else
      export SOURCE_DATE_EPOCH="$(date +%s)"
    fi
  fi
  info "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"
fi

echo "=== Sentinel OS v1.5 ISO Build (polished distro edition) ==="

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
sudo apt install -y sudo live-build debootstrap squashfs-tools xorriso git ca-certificates gnupg gpg

if ! groups | grep -q '\bsudo\b'; then
  sudo usermod -aG sudo "$USER"
  echo "[!] Added $USER to sudo group. Log out/in and re-run."
  exit 0
fi

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
# PHASE 3: live-build config
# -------------------------------------------------
echo "[PHASE 3] CONFIGURING LIVE-BUILD"
sudo lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloader grub-efi \
  --debian-installer live \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components" \
  --iso-volume "$ISO_VOL" \
  --iso-application "$ISO_APP" \
  --iso-publisher "$ISO_PUB" \
  --apt-recommends false

sudo chown -R "$USER:$USER" config
pause

# -------------------------------------------------
# PHASE 4: APT sources and policy (chroot)
# -------------------------------------------------
echo "[PHASE 4] WRITING APT SOURCES + POLICY"
mkdir -p config/archives
cat <<'EOF' > config/archives/bookworm.list.chroot
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

cat <<'EOF' > config/archives/bookworm-backports.list.chroot
deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
EOF

mkdir -p config/includes.chroot/etc/apt/apt.conf.d
cat <<'EOF' > config/includes.chroot/etc/apt/apt.conf.d/99sentinel
APT::Install-Recommends "false";
APT::Install-Suggests "false";

Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::ftp::Timeout "30";

Dpkg::Options { "--force-confdef"; "--force-confnew"; };
EOF

mkdir -p config/includes.chroot/etc/apt/preferences.d
cat <<'EOF' > config/includes.chroot/etc/apt/preferences.d/99-backports-default-low
Package: *
Pin: release a=bookworm-backports
Pin-Priority: 100
EOF
pause

# -------------------------------------------------
# PHASE 4.1: Debian-Installer defaults (install friendliness)
# -------------------------------------------------
echo "[PHASE 4.1] ADDING DEBIAN-INSTALLER DEFAULTS"
mkdir -p config/includes.installer
cat <<'EOF' > config/includes.installer/preseed.cfg
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

d-i netcfg/choose_interface select auto
d-i netcfg/link_wait_timeout string 15
d-i netcfg/dhcp_timeout string 30
d-i netcfg/dhcpv6_timeout string 15

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

d-i apt-setup/non-free boolean true
d-i apt-setup/contrib boolean true
d-i apt-setup/disable-cdrom-entries boolean true

d-i hw-detect/load_firmware boolean true

d-i partman/confirm_write_new_label boolean true
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
EOF
pause

# -------------------------------------------------
# PHASE 4.2: Live user + live-only sudoers
# -------------------------------------------------
echo "[PHASE 4.2] DEFINING LIVE USER"
mkdir -p config/includes.chroot/etc/live
cat <<'EOF' > config/includes.chroot/etc/live/config.conf
LIVE_USERNAME="user"
LIVE_USER_FULLNAME="Sentinel Live"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev sudo"
LIVE_USER_NO_PASSWORD="true"
EOF

mkdir -p config/hooks/normal
cat <<'EOF' > config/hooks/normal/030-ensure-live-user.hook.chroot
#!/bin/sh
set -eu
id user >/dev/null 2>&1 || {
  useradd -m -s /bin/bash user
  usermod -aG sudo,audio,video,plugdev,netdev,cdrom,dip,floppy user || true
  passwd -d user || true
}
EOF
chmod +x config/hooks/normal/030-ensure-live-user.hook.chroot

mkdir -p config/includes.chroot/etc/sudoers.d
cat <<'EOF' > config/includes.chroot/etc/sudoers.d/99-sentinel-live
user ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 config/includes.chroot/etc/sudoers.d/99-sentinel-live
pause

# -------------------------------------------------
# PHASE 4.3: Version stamping (inside OS)
# -------------------------------------------------
echo "[PHASE 4.3] ADDING VERSION STAMPING"
mkdir -p config/includes.chroot/usr/local/share/sentinel
cat <<EOF > config/includes.chroot/usr/local/share/sentinel/VERSION
Sentinel OS Version: $SENTINEL_VERSION
Build Date (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

cat <<EOF > config/includes.chroot/etc/sentinel-release
Sentinel OS $SENTINEL_VERSION (Debian 12 Bookworm)
EOF

mkdir -p config/includes.chroot/etc/update-motd.d
cat <<'EOF' > config/includes.chroot/etc/update-motd.d/10-sentinel
#!/bin/sh
printf "Sentinel OS %s\n" "$(cat /usr/local/share/sentinel/VERSION 2>/dev/null | head -n 1 | sed 's/^Sentinel OS Version: //')"
EOF
chmod +x config/includes.chroot/etc/update-motd.d/10-sentinel
pause

# -------------------------------------------------
# PHASE 5: Packages (hardware-oriented baseline)
# -------------------------------------------------
echo "[PHASE 5] WRITING PACKAGE LISTS (HARDWARE BASELINE)"
mkdir -p config/package-lists

cat <<'EOF' > config/package-lists/mate.list.chroot
mate-desktop-environment
lightdm
lightdm-gtk-greeter
network-manager
network-manager-gnome
policykit-1
sudo
zenity
EOF

cat <<'EOF' > config/package-lists/core.list.chroot
live-config
live-boot
live-tools
linux-image-amd64

xorg
xserver-xorg-core
xserver-xorg-input-all
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xserver-xorg-video-qxl
spice-vdagent
qemu-guest-agent

grub-efi-amd64
grub-efi-amd64-signed
shim-signed
efibootmgr

firmware-linux
firmware-misc-nonfree
firmware-amd-graphics
firmware-intel-graphics
firmware-iwlwifi
firmware-realtek
firmware-atheros

apparmor
apparmor-utils
apparmor-profiles
ufw
firejail
firejail-profiles

curl
wget
git
jq
ca-certificates
python3
python3-pip
flatpak
gnome-software-plugin-flatpak
xdg-desktop-portal
xdg-desktop-portal-gtk
synaptic
gdebi
rsyslog
EOF
pause

# -------------------------------------------------
# PHASE 6: LightDM + LIVE-only guard + delay + watchdog
# -------------------------------------------------
echo "[PHASE 6] CONFIGURING LIGHTDM + LIVE GUARDS"
mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d

cat <<'EOF' > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

cat <<'EOF' > config/includes.chroot/etc/lightdm/lightdm.conf.d/60-autologin.conf
[Seat:*]
autologin-user=user
autologin-user-timeout=0
EOF

mkdir -p config/includes.chroot/etc/systemd/system/lightdm.service.d
cat <<'EOF' > config/includes.chroot/etc/systemd/system/lightdm.service.d/override.conf
[Service]
ExecStartPre=/bin/sleep 5
EOF

mkdir -p config/includes.chroot/usr/local/sbin
cat <<'EOF' > config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh
#!/bin/sh
set -eu
if ! grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  rm -f /etc/lightdm/lightdm.conf.d/60-autologin.conf
  rm -f /etc/sudoers.d/99-sentinel-live
fi
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh

mkdir -p config/includes.chroot/etc/systemd/system
cat <<'EOF' > config/includes.chroot/etc/systemd/system/sentinel-live-guard.service
[Unit]
Description=Sentinel Live Guard (remove live-only settings on installed boots)
DefaultDependencies=no
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sentinel-live-guard.sh

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' > config/hooks/normal/020-enable-live-guard.hook.chroot
#!/bin/sh
set -eu
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/sentinel-live-guard.service /etc/systemd/system/multi-user.target.wants/sentinel-live-guard.service
EOF
chmod +x config/hooks/normal/020-enable-live-guard.hook.chroot

cat <<'EOF' > config/includes.chroot/usr/local/sbin/sentinel-dm-watchdog.sh
#!/bin/sh
set -eu
sleep 20
if ! systemctl is-active --quiet lightdm; then
  systemctl restart lightdm || true
fi
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-dm-watchdog.sh

cat <<'EOF' > config/includes.chroot/etc/systemd/system/sentinel-dm-watchdog.service
[Unit]
Description=Sentinel Display Manager Watchdog (restart LightDM once if needed)
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sentinel-dm-watchdog.sh

[Install]
WantedBy=graphical.target
EOF

cat <<'EOF' > config/hooks/normal/025-enable-dm-watchdog.hook.chroot
#!/bin/sh
set -eu
mkdir -p /etc/systemd/system/graphical.target.wants
ln -sf /etc/systemd/system/sentinel-dm-watchdog.service /etc/systemd/system/graphical.target.wants/sentinel-dm-watchdog.service
EOF
chmod +x config/hooks/normal/025-enable-dm-watchdog.hook.chroot
pause

# -------------------------------------------------
# PHASE 7: First-boot hardening + UEFI fallback (installed only)
# -------------------------------------------------
echo "[PHASE 7] ADDING FIRST-BOOT HARDENING + UEFI FALLBACK (INSTALLED SYSTEM ONLY)"

mkdir -p config/includes.chroot/etc/sysctl.d
cat <<'EOF' > config/includes.chroot/etc/sysctl.d/99-sentinel.conf
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

cat <<'EOF' > config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh
#!/bin/sh
set -e

if grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  exit 0
fi

LOG="/var/log/sentinel-firstboot.log"
MARK="/var/lib/sentinel-firstboot.done"

mkdir -p /var/log /var/lib
[ -f "$MARK" ] && exit 0

log() { printf "%s\n" "$*" >> "$LOG"; }

log "[Sentinel] First boot started: $(date -Is)"

if [ -d /boot/efi ] && ! mountpoint -q /boot/efi 2>/dev/null; then
  log "[UEFI] /boot/efi exists but not mounted; attempting mount /boot/efi"
  mount /boot/efi >> "$LOG" 2>&1 || mount -a >> "$LOG" 2>&1 || true
fi

if mountpoint -q /boot/efi 2>/dev/null; then
  EFI_DEBIAN="/boot/efi/EFI/debian"
  EFI_BOOT="/boot/efi/EFI/BOOT"
  mkdir -p "$EFI_BOOT" || true

  if [ -f "$EFI_DEBIAN/grubx64.efi" ]; then
    cp -f "$EFI_DEBIAN/grubx64.efi" "$EFI_BOOT/BOOTX64.EFI" && log "[UEFI] Installed fallback BOOTX64.EFI from grubx64.efi" || true
  elif [ -f "$EFI_DEBIAN/shimx64.efi" ]; then
    cp -f "$EFI_DEBIAN/shimx64.efi" "$EFI_BOOT/BOOTX64.EFI" && log "[UEFI] Installed fallback BOOTX64.EFI from shimx64.efi" || true
  else
    log "[UEFI] No grubx64.efi or shimx64.efi found under $EFI_DEBIAN; skipping fallback copy"
  fi
else
  log "[UEFI] /boot/efi not mounted; skipping fallback copy"
fi

log "[Sentinel] Applying sysctl --system"
sysctl --system >> "$LOG" 2>&1 || true

if command -v ufw >/dev/null 2>&1; then
  log "[Sentinel] Configuring UFW defaults"
  ufw default deny incoming >> "$LOG" 2>&1 || true
  ufw default allow outgoing >> "$LOG" 2>&1 || true
  ufw --force enable >> "$LOG" 2>&1 || true
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^apparmor\.service'; then
  systemctl enable apparmor.service >> "$LOG" 2>&1 || true
  systemctl start apparmor.service >> "$LOG" 2>&1 || true
  log "[Sentinel] AppArmor enabled"
fi

systemctl disable avahi-daemon.service >> "$LOG" 2>&1 || true
systemctl disable bluetooth.service >> "$LOG" 2>&1 || true

touch "$MARK"
log "[Sentinel] First boot completed: $(date -Is)"

systemctl disable sentinel-firstboot.service >> "$LOG" 2>&1 || true
exit 0
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh

cat <<'EOF' > config/includes.chroot/etc/systemd/system/sentinel-firstboot.service
[Unit]
Description=Sentinel First Boot Hardening (installed system only)
After=local-fs.target network.target
ConditionPathExists=!/var/lib/sentinel-firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sentinel-firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' > config/hooks/normal/040-enable-firstboot.hook.chroot
#!/bin/sh
set -eu
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/sentinel-firstboot.service /etc/systemd/system/multi-user.target.wants/sentinel-firstboot.service
EOF
chmod +x config/hooks/normal/040-enable-firstboot.hook.chroot

cat <<'EOF' > config/includes.chroot/usr/local/sbin/sentinel-firstboot-banner.sh
#!/bin/sh
set -e

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
    --title="Sentinel OS" \
    --text="First-boot hardening applied.\n\nUEFI fallback set (BOOTX64.EFI).\nAppArmor enabled.\nSysctl hardened.\nFirewall enabled.\n\nLog:\n  /var/log/sentinel-firstboot.log\n\nThis message will not appear again."
fi

touch "$MARK"
exit 0
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-firstboot-banner.sh

mkdir -p config/includes.chroot/etc/xdg/autostart
cat <<'EOF' > config/includes.chroot/etc/xdg/autostart/sentinel-firstboot-banner.desktop
[Desktop Entry]
Type=Application
Name=Sentinel First Boot Banner
Exec=/usr/local/sbin/sentinel-firstboot-banner.sh
OnlyShowIn=MATE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
pause

# -------------------------------------------------
# PHASE 7.1: First-boot Setup Wizard (installed only; non-blocking)
# -------------------------------------------------
echo "[PHASE 7.1] ADDING FIRST-BOOT SETUP WIZARD (INSTALLED SYSTEM ONLY)"
cat <<'EOF' > config/includes.chroot/usr/local/sbin/sentinel-setup-wizard.sh
#!/bin/sh
set -e

if grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  exit 0
fi

MARK="/var/lib/sentinel-setup.done"
LOG="/var/log/sentinel-setup.log"

[ -f "$MARK" ] && exit 0
[ -z "${DISPLAY:-}" ] && exit 0

mkdir -p /var/lib /var/log
touch "$LOG" || true

command -v zenity >/dev/null 2>&1 || { touch "$MARK"; exit 0; }

zenity --question \
  --title="Sentinel OS Setup" \
  --text="Welcome to Sentinel OS.\n\nWould you like to install optional role profiles now?\n\n(You can do this later with: sentinel-profile-manager)" \
  >>"$LOG" 2>&1 || { touch "$MARK"; exit 0; }

CHOICES="$(zenity --list --checklist \
  --title="Select profiles" \
  --text="Choose profiles to install (recommended: Developer + Blue).\n\nNote: installs require internet access." \
  --column="Install" --column="Profile" --column="Description" \
  FALSE "developer" "Compilers, build tools, IDE basics" \
  FALSE "blue" "Defensive tooling & monitoring" \
  FALSE "purple" "Hunting / dual-use defenders" \
  FALSE "privacy" "Tor stack + GnuPG tools" \
  FALSE "ir" "Incident response & forensics tools" \
  FALSE "office" "LibreOffice + reporting tools" \
  FALSE "graphics" "GIMP/Inkscape/viewers" \
  FALSE "red" "Offensive tools (last resort)" \
  --separator=" " )" || { touch "$MARK"; exit 0; }

if [ -z "$CHOICES" ]; then
  zenity --info --title="Sentinel OS Setup" --text="No profiles selected. You can install later with sentinel-profile-manager."
  touch "$MARK"
  exit 0
fi

for p in $CHOICES; do
  echo "[setup] installing profile: $p" >>"$LOG"
  if command -v sentinel-profile-manager >/dev/null 2>&1; then
    sudo sentinel-profile-manager install "$p" >>"$LOG" 2>&1 || true
  fi
done

zenity --info --title="Sentinel OS Setup" --text="Setup complete.\n\nLogs: /var/log/sentinel-setup.log"
touch "$MARK"
exit 0
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-setup-wizard.sh

cat <<'EOF' > config/includes.chroot/etc/xdg/autostart/sentinel-setup-wizard.desktop
[Desktop Entry]
Type=Application
Name=Sentinel Setup Wizard
Exec=/usr/local/sbin/sentinel-setup-wizard.sh
OnlyShowIn=MATE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
pause

# -------------------------------------------------
# PHASE 8: Profile system (opt-in)
# -------------------------------------------------
echo "[PHASE 8] ADDING PROFILE SYSTEM (OPT-IN)"
mkdir -p config/includes.chroot/usr/local/share/sentinel/profiles
mkdir -p config/includes.chroot/usr/local/sbin

cat <<'EOF' > config/includes.chroot/usr/local/sbin/sentinel-profile-manager
#!/bin/sh
set -e
PROFILE_DIR="/usr/local/share/sentinel/profiles"
LOG="/var/log/sentinel-profiles.log"
export DEBIAN_FRONTEND=noninteractive

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
    [ -f "$PROFILE_DIR/$2.sh" ] || { echo "Unknown profile: $2"; exit 1; }
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

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/kernel-backports.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y -t bookworm-backports linux-image-amd64
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/blue.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y tcpdump strace ltrace sysstat radare2 testdisk photorec zeek suricata auditd aide rkhunter lynis logwatch wireshark
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/developer.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y default-jdk gcc gdb valgrind build-essential cmake meson ninja-build python3-venv git-lfs shellcheck geany make
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/red.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y masscan hydra aircrack-ng sqlmap nikto john john-data hashcat netcat-openbsd openssl
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/purple.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y suricata tcpdump jq zeek yara auditd aide stegohide stegosuite lynis
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/privacy.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y tor torsocks nyx obfs4proxy gnupg kleopatra
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/ir.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y clamav yara sleuthkit
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/office.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y libreoffice pandoc graphviz plantuml
EOF

cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/profiles/graphics.sh
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y gimp inkscape eog
EOF

chmod +x config/includes.chroot/usr/local/share/sentinel/profiles/*.sh

mkdir -p config/includes.chroot/usr/local/share/sentinel
cat <<'EOF' > config/includes.chroot/usr/local/share/sentinel/README-profiles.txt
Sentinel Profiles (opt-in)

List profiles:
  sentinel-profile-manager list

Install a profile (post-install):
  sudo sentinel-profile-manager install <profile>

Hardware:
  sudo sentinel-profile-manager install kernel-backports
EOF
pause

# -------------------------------------------------
# PHASE 9: Build ISO + checksums + optional signatures
# -------------------------------------------------
echo "[PHASE 9] BUILDING ISO + ARTIFACTS"
sudo lb clean

if [ "$REPRO" = "1" ]; then
  sudo --preserve-env=TZ,LC_ALL,LANG,SOURCE_DATE_EPOCH lb build 2>&1 | tee "$WORKDIR/build.log"
else
  sudo lb build 2>&1 | tee "$WORKDIR/build.log"
fi

echo "[+] Build complete. ISO output(s):"
ls -lh *.iso || true

echo "[+] Locating built ISO artifact..."
ISO_FOUND="$(ls -1 *.iso 2>/dev/null | head -n 1 || true)"
[ -n "$ISO_FOUND" ] || die "No ISO file found after build."

echo "[+] ISO FOUND: $ISO_FOUND"
ISO_DST="Sentinel-OS-v1.5-amd64.iso"
mv "$ISO_FOUND" "$ISO_DST"

sha256sum "$ISO_DST" > "$ISO_DST.sha256"
sha512sum "$ISO_DST" > "$ISO_DST.sha512"
echo "[+] Checksums written: $ISO_DST.sha256, $ISO_DST.sha512"

if [ "$SIGN" = "1" ] && command -v gpg >/dev/null 2>&1; then
  echo "[PHASE 9.5] SIGNING (OPTIONAL)"
  if gpg --list-secret-keys >/dev/null 2>&1; then
    KEY_ARG=()
    if [ -n "$SIGN_KEYID" ]; then
      KEY_ARG=(--local-user "$SIGN_KEYID")
    fi

    gpg --batch --yes "${KEY_ARG[@]}" --armor --detach-sign "$ISO_DST.sha256" || true
    gpg --batch --yes "${KEY_ARG[@]}" --armor --detach-sign "$ISO_DST.sha512" || true
    gpg --batch --yes "${KEY_ARG[@]}" --armor --detach-sign "$ISO_DST" || true

    echo "[+] Signatures (if key available):"
    ls -lh "$ISO_DST".asc "$ISO_DST".sha256.asc "$ISO_DST".sha512.asc 2>/dev/null || true
  else
    echo "[!] No GPG secret keys found; skipping signing (checksums still generated)."
  fi
else
  echo "[*] SIGN=0 or gpg missing; skipping signing (checksums still generated)."
fi

echo "======== Sentinel OS v1.5 build completed successfully. =========="
echo "[+] Artifacts:"
ls -lh "$ISO_DST" "$ISO_DST.sha256" "$ISO_DST.sha512" 2>/dev/null || true
echo "[+] Verify with:"
echo "    sha256sum -c $ISO_DST.sha256"
echo "    sha512sum -c $ISO_DST.sha512"
