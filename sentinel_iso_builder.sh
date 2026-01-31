#!/usr/bin/env bash
# Sentinel OS v1.0 ISO Build – Phased Interactive Script (Bookworm-safe)
# Base: Debian 12 (Bookworm) amd64
# live-build version: 20230502 compatible
#
# IMPORTANT:
# - Run as a normal user (e.g. 'builder'), NOT root
# - User must have sudo access
# - This script intentionally avoids unsupported live-build flags

set -euo pipefail

pause() {
  echo
  read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."
  echo
}

# -------------------------------------------------
# Pre-flight guard
# -------------------------------------------------
if [ "$EUID" -eq 0 ]; then
  echo "[!] Do not run this script as root."
  exit 1
fi

echo "=== Sentinel OS v1.0 ISO Build (Phased, Bookworm-safe) ==="

# -------------------------------------------------
# PHASE 0: Sanity checks
# -------------------------------------------------
echo "[PHASE 0] Sanity checks"

ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" != "amd64" ]; then
  echo "[!] ERROR: Host architecture is $ARCH (expected amd64)"
  exit 1
fi
echo "[+] Architecture OK (amd64)"

if ! command -v sudo >/dev/null 2>&1; then
  echo "[!] sudo not installed"
  exit 1
fi

pause

# -------------------------------------------------
# PHASE 1: Install build dependencies
# -------------------------------------------------
echo "[PHASE 1] Installing build dependencies"

sudo apt update
sudo apt install -y   sudo live-build debootstrap squashfs-tools xorriso   git ca-certificates gnupg

if ! groups | grep -q '\bsudo\b'; then
  echo "[*] Adding user to sudo group"
  sudo usermod -aG sudo "$USER"
  echo "[!] Log out and back in, then re-run the script."
  exit 0
fi

# Ensure debootstrap is discoverable in all contexts
if [ ! -x /usr/bin/debootstrap ]; then
  sudo ln -sf /usr/sbin/debootstrap /usr/bin/debootstrap
fi

echo "[+] Dependencies installed"
pause

# -------------------------------------------------
# PHASE 2: Prepare workspace
# -------------------------------------------------
echo "[PHASE 2] Preparing workspace"

WORKDIR="$HOME/sentinel-iso"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

sudo lb clean --purge || true
rm -rf .build cache || true

echo "[+] Workspace ready at $WORKDIR"
pause

# -------------------------------------------------
# PHASE 3: live-build configuration (Bookworm-safe)
# -------------------------------------------------
echo "[PHASE 3] Configuring live-build (native amd64 bootstrap)"

sudo lb config   --distribution bookworm   --architectures amd64   --bootstrap debootstrap   --binary-images iso-hybrid   --debian-installer live   --archive-areas "main"   --bootappend-live "boot=live components quiet splash"   --iso-volume "Sentinel OS 1.0"   --iso-application "Sentinel OS"   --iso-publisher "Sentinel OS Project"   --apt-recommends false

echo "[+] live-build configured"
pause

# -------------------------------------------------
# PHASE 4: APT sources and policy
# -------------------------------------------------
echo "[PHASE 4] Writing APT sources and policies"

mkdir -p config/archives
cat << EOF > config/archives/bookworm.list.chroot
deb http://deb.debian.org/debian bookworm main
deb http://security.debian.org/debian-security bookworm-security main
EOF

mkdir -p config/includes.chroot/etc/apt/apt.conf.d
cat << EOF > config/includes.chroot/etc/apt/apt.conf.d/99sentinel
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

echo "[+] APT configuration written"
pause

# -------------------------------------------------
# PHASE 5: Package lists
# -------------------------------------------------
echo "[PHASE 5] Creating package lists"

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
EOF

cat << EOF > config/package-lists/sentinel-core.list.chroot
apparmor
apparmor-utils
apparmor-profiles
firejail
firejail-profiles
ufw
nmap
wireshark
zeek
rsyslog
lynis
openvas
yara
osquery
plaso
sleuthkit
clamav
gnupg
kleopatra
cryptsetup
veracrypt
tor
torbrowser-launcher
torsocks
nyx
obfs4proxy
libreoffice
pandoc
graphviz
plantuml
mousepad
curl
wget
git
jq
ca-certificates
python3
python3-pip
EOF

echo "[+] Package lists created"
pause

# -------------------------------------------------
# PHASE 6: LightDM configuration
# -------------------------------------------------
echo "[PHASE 6] Configuring LightDM for MATE"

mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
cat << EOF > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf
[SeatDefaults]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

echo "[+] LightDM configured"
pause

# -------------------------------------------------
# PHASE 7: Hardening hook
# -------------------------------------------------
echo "[PHASE 7] Installing hardening hook"

mkdir -p config/hooks/normal
cat << 'EOF' > config/hooks/normal/001-sentinel-hardening.hook.chroot
#!/bin/sh
set -e
systemctl enable apparmor || true
ufw default deny incoming || true
ufw default allow outgoing || true
ufw enable || true
systemctl disable avahi-daemon.service || true
systemctl disable bluetooth.service || true
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
sysctl --system || true
EOF

chmod +x config/hooks/normal/001-sentinel-hardening.hook.chroot

echo "[+] Hardening hook installed"
pause

# -------------------------------------------------
# PHASE 8: Build ISO
# -------------------------------------------------
echo "[PHASE 8] Building Sentinel OS ISO"
echo "[!] This may take 20–60 minutes"

sudo lb clean --purge
sudo lb build

echo "[+] Build completed"
ls -lh *.iso || true

echo "=== Sentinel OS ISO build finished ==="
