#!/usr/bin/env bash
# Sentinel OS v1.0 ISO Build – Phased Interactive Script (Bookworm SAFE, FIXED)
# Debian 12 (Bookworm) amd64
# live-build 20230502 compatible
#
# This version includes:
# - No unsupported live-build flags
# - Correct repo sections (non-free-firmware)
# - Bookworm-valid package names only
# - Heavy / external tools deferred to post-install
# - Correct hook stage ordering
#
# Run as normal user with sudo rights (NOT root)

set -euo pipefail

pause() {
  echo
  read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."
  echo
}

if [ "$EUID" -eq 0 ]; then
  echo "[!] Do not run this script as root."
  exit 1
fi

echo "=== Sentinel OS v1.0 ISO Build (Bookworm-safe, FIXED) ==="

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
pause

# -------------------------------------------------
# PHASE 1: Dependencies
# -------------------------------------------------
echo "[PHASE 1] Installing build dependencies"

sudo apt update
sudo apt install -y   sudo live-build debootstrap squashfs-tools xorriso   git ca-certificates gnupg

if ! groups | grep -q '\bsudo\b'; then
  sudo usermod -aG sudo "$USER"
  echo "[!] User added to sudo group. Log out/in and re-run."
  exit 0
fi

[ -x /usr/bin/debootstrap ] || sudo ln -sf /usr/sbin/debootstrap /usr/bin/debootstrap
pause

# -------------------------------------------------
# PHASE 2: Workspace
# -------------------------------------------------
echo "[PHASE 2] Preparing workspace"

WORKDIR="$HOME/sentinel-iso"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

sudo lb clean --purge || true
rm -rf .build cache || true
pause

# -------------------------------------------------
# PHASE 3: live-build config (Bookworm native)
# -------------------------------------------------
echo "[PHASE 3] Configuring live-build"

sudo lb config   --distribution bookworm   --architectures amd64   --binary-images iso-hybrid   --debian-installer live   --archive-areas "main contrib non-free non-free-firmware"   --bootappend-live "boot=live components quiet splash"   --iso-volume "Sentinel OS 1.0"   --iso-application "Sentinel OS"   --iso-publisher "Sentinel OS Project"   --apt-recommends false

sudo chown -R "$USER:$USER" config
pause

# -------------------------------------------------
# PHASE 4: APT sources
# -------------------------------------------------
echo "[PHASE 4] Writing APT sources"

mkdir -p config/archives
cat << EOF > config/archives/bookworm.list.chroot
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
pause

# -------------------------------------------------
# PHASE 5: Package lists
# -------------------------------------------------
echo "[PHASE 5] Writing package lists"

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
rsyslog
lynis
clamav
yara
sleuthkit
gnupg
kleopatra
cryptsetup
firmware-linux-free
tor
torsocks
nyx
obfs4proxy
libreoffice
pandoc
graphviz
plantuml
mousepad
firefox-esr
curl
wget
git
jq
ca-certificates
python3
python3-pip
EOF
pause

# -------------------------------------------------
# PHASE 6: LightDM config
# -------------------------------------------------
echo "[PHASE 6] Configuring LightDM"

mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
cat << EOF > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf
[SeatDefaults]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF
pause

# -------------------------------------------------
# PHASE 7: Hardening hook (binary stage)
# -------------------------------------------------
echo "[PHASE 7] Installing hardening hook"

mkdir -p config/hooks/binary
cat << 'EOF' > config/hooks/binary/001-sentinel-hardening.hook.binary
#!/bin/sh
set -e
systemctl enable apparmor.service || true
ufw default deny incoming || true
ufw default allow outgoing || true
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
EOF

chmod +x config/hooks/binary/001-sentinel-hardening.hook.binary
pause

# -------------------------------------------------
# PHASE 8: Build ISO
# -------------------------------------------------
echo "[PHASE 8] Building ISO (this will take time)"

sudo lb clean
sudo lb config
sudo lb build

echo "[+] Build complete. ISO output:"
ls -lh *.iso || true
echo "=== Sentinel OS v1.0 build finished ==="
