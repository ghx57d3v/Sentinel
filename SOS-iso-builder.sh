#!/usr/bin/env bash
# Sentinel OS v1.0 ISO Build Script
# Debian 12 (Bookworm) amd64
#
# Scope:
# - Live boot on real hardware
# - Bare-metal installation
# - NO virtual machine / hypervisor support


set -euo pipefail

pause() { read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."; }
die() { echo "[!] $*" >&2; exit 1; }

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  die "Do not run as root. Run as a normal user with sudo."
fi

echo "=== Sentinel OS v1.0.1 ISO Build ==="

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
sudo apt install -y \
  live-build debootstrap squashfs-tools xorriso git \
  ca-certificates gnupg

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
sudo rm -rf .build cache || true
pause

# -------------------------------------------------
# PHASE 3: live-build config
# -------------------------------------------------
echo "[PHASE 3] CONFIGURING LIVE-BUILD"

sudo lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloaders "grub-pc grub-efi" \
  --linux-flavours amd64 \
  --linux-packages "linux-image linux-headers" \
  --debian-installer live \
  --debian-installer-gui true \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components quiet splash live-media-path=/live" \
  --iso-volume "Sentinel OS v1.0" \
  --iso-application "Sentinel OS" \
  --iso-publisher "Sentinel OS Project" \
  --apt-recommends false

sudo chown -R "$USER:$USER" config

cat <<'EOF' | sudo tee config/binary >/dev/null
LB_BINARY_IMAGES="iso-hybrid"
LB_BOOTLOADERS="grub-pc grub-efi"
LB_LINUX_FLAVOURS="amd64"
LB_LINUX_PACKAGES="linux-image linux-headers"
EOF
sudo chown "$USER:$USER" config/binary

pause
echo "[PHASE 4] APT + DESKTOP FILESYSTEM SETUP"

mkdir -p config/archives
mkdir -p config/includes.chroot/etc/apt/apt.conf.d

# -------------------------------------------------
# Desktop / UI directories (system-wide)
# -------------------------------------------------

# Wallpapers
mkdir -p config/includes.chroot/usr/share/backgrounds/sentinel

# Icon themes
mkdir -p config/includes.chroot/usr/share/icons
mkdir -p config/includes.chroot/usr/share/icons/sentinel

# GTK / theme directories
mkdir -p config/includes.chroot/usr/share/themes
mkdir -p config/includes.chroot/usr/share/themes/sentinel

# MATE defaults (system-wide)
mkdir -p config/includes.chroot/etc/skel/.config
mkdir -p config/includes.chroot/etc/skel/.config/mate
mkdir -p config/includes.chroot/etc/skel/.config/mate/desktop
mkdir -p config/includes.chroot/etc/skel/.config/mate/desktop/background
mkdir -p config/includes.chroot/etc/skel/.config/mate/interface

# dconf defaults (preferred over gsettings at build time)
mkdir -p config/includes.chroot/etc/dconf/db/local.d
mkdir -p config/includes.chroot/etc/dconf/profile

pause

# -------------------------------------------------
# PHASE 5: Package lists (bare-metal only)
# -------------------------------------------------
echo "[PHASE 5] PACKAGE LISTS"
mkdir -p config/package-lists

cat > config/package-lists/10-desktop-mate.list.chroot <<'EOF'
mate-desktop-environment
lightdm
lightdm-gtk-greeter
network-manager
network-manager-gnome
policykit-1
sudo
zenity
EOF

cat > config/package-lists/20-sentinel-core.list.chroot <<'EOF'
# Live system
live-boot
live-config
live-tools
firmware-linux
firmware-linux-nonfree
firmware-misc-nonfree

# Kernel
linux-image-amd64

# Xorg + real hardware drivers only
xorg
xserver-xorg-core
xserver-xorg-input-all
xserver-xorg-video-intel
xserver-xorg-video-amdgpu
xserver-xorg-video-nouveau

# Baseline security
apparmor
apparmor-utils
apparmor-profiles
ufw
unattended-upgrades
needrestart
chrony

# Essentials
ca-certificates
gnupg
gdebi
synaptic
make
mousepad
cmake
firefox-esr
epiphany-browser
geany
gimp
inkscape
libreoffice
curl
wget
git
jq
python3
EOF
pause

# -------------------------------------------------
# PHASE 6: Live user + LightDM
# -------------------------------------------------
echo "[PHASE 6] LIVE USER + DISPLAY"

mkdir -p config/includes.chroot/etc/live
cat > config/includes.chroot/etc/live/config.conf <<'EOF'
LIVE_USER="user"
LIVE_USER_FULLNAME="Sentinel Live"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev sudo"
LIVE_USER_PASSWORD="live"
EOF

mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/60-sentinel-live-autologin.conf <<'EOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
EOF

mkdir -p config/includes.chroot/usr/local/sbin
cat > config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh <<'EOF'
#!/bin/sh
set -eu
if ! grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  rm -f /etc/lightdm/lightdm.conf.d/60-sentinel-live-autologin.conf
fi
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh

mkdir -p config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/etc/systemd/system/sentinel-live-guard.service <<'EOF'
[Unit]
Description=Sentinel Live Autologin Guard
DefaultDependencies=no
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sentinel-live-guard.sh

[Install]
WantedBy=multi-user.target
EOF
pause

# -------------------------------------------------
# PHASE 7: Sysctl hardening (files only)
# -------------------------------------------------
echo "[PHASE 7] SYSCTL HARDENING"
mkdir -p config/includes.chroot/etc/sysctl.d
cat > config/includes.chroot/etc/sysctl.d/99-sentinel.conf <<'EOF'
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
# PHASE 8: First-boot hardening (installed system only)
# -------------------------------------------------
echo "[PHASE 8] FIRST-BOOT HARDENING"

cat > config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh <<'EOF'
#!/bin/sh
set -eu

if grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  exit 0
fi

LOG="/var/log/sentinel-firstboot.log"
MARK="/var/lib/sentinel-firstboot.done"
mkdir -p /var/lib

[ -f "$MARK" ] && exit 0

sysctl --system >> "$LOG" 2>&1 || true

if command -v ufw >/dev/null 2>&1; then
  ufw default deny incoming >> "$LOG" 2>&1 || true
  ufw default allow outgoing >> "$LOG" 2>&1 || true
  ufw --force enable >> "$LOG" 2>&1 || true
fi

systemctl enable apparmor.service >> "$LOG" 2>&1 || true
systemctl start apparmor.service >> "$LOG" 2>&1 || true
systemctl disable avahi-daemon.service >> "$LOG" 2>&1 || true
systemctl disable bluetooth.service >> "$LOG" 2>&1 || true

touch "$MARK"
systemctl disable sentinel-firstboot.service >> "$LOG" 2>&1 || true
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh

cat > config/includes.chroot/etc/systemd/system/sentinel-firstboot.service <<'EOF'
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
pause

# -------------------------------------------------
# PHASE 9: Enable services
# -------------------------------------------------
echo "[PHASE 9] ENABLE SERVICES"
mkdir -p config/hooks/normal
cat > config/hooks/normal/090-enable-services.hook.chroot <<'EOF'
#!/bin/sh
set -eu
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/sentinel-live-guard.service \
  /etc/systemd/system/multi-user.target.wants/sentinel-live-guard.service
ln -sf /etc/systemd/system/sentinel-firstboot.service \
  /etc/systemd/system/multi-user.target.wants/sentinel-firstboot.service
EOF
chmod +x config/hooks/normal/090-enable-services.hook.chroot
pause

# -------------------------------------------------
# PHASE 10: Build ISO
# -------------------------------------------------
echo "[PHASE 10] BUILDING ISO"
sudo lb clean --purge
sudo lb build 2>&1 | tee "$WORKDIR/build.log"
ISO_FOUND="$(ls -1 *.iso 2>/dev/null | head -n1 || true)"
[ -n "$ISO_FOUND" ] || die "No ISO produced."

ISO_DST="Sentinel-OS-v1.0.1-amd64.iso"
mv "$ISO_FOUND" "$ISO_DST"
sha256sum "$ISO_DST" > "$ISO_DST.sha256"

echo "[+] Built:"
ls -lh "$ISO_DST" "$ISO_DST.sha256"
