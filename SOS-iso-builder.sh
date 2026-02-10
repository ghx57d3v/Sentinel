#!/usr/bin/env bash
# Sentinel OS v1 ISO Build Script
# Debian 12 (Bookworm) amd64 + MATE
#
# Production Iterations Included:
# - Iteration 2: Signed Sentinel APT repository (no local .deb shipping)
# - Iteration 3: Release artifacts, manifests, checksums, signatures
#
# Secure Boot intentionally deferred.

set -euo pipefail

pause() { read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."; }
die() { echo "[!] $*" >&2; exit 1; }

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  die "Do not run as root. Run as a normal user with sudo."
fi

echo "=== Sentinel OS v1 ISO Build (Production) ==="

# -------------------------------------------------
# GLOBALS (Iteration 2/3)
# -------------------------------------------------
SENTINEL_VERSION="1.0.0"
SENTINEL_DIST="bookworm"
SENTINEL_ARCH="amd64"

# Sentinel repo (Iteration 2)
SENTINEL_REPO_URL="https://repo.sentinel.example/apt"
SENTINEL_REPO_COMPONENT="main"
SENTINEL_KEYRING_PKG="sentinel-keyring"

# Signing (Iteration 3)
SIGNING_TOOL="minisign"     # or "gpg"
SIGNING_KEY_ID=""           # optional; depends on tool

# -------------------------------------------------
# PHASE 0: Sanity checks
# -------------------------------------------------
echo "[PHASE 0] SANITY CHECKS"
ARCH="$(dpkg --print-architecture)"
[ "$ARCH" = "$SENTINEL_ARCH" ] || die "Host architecture is $ARCH (expected $SENTINEL_ARCH)."

command -v lb >/dev/null 2>&1 || echo "[!] live-build not installed yet (will be installed next)"
pause

# -------------------------------------------------
# PHASE 1: Dependencies
# -------------------------------------------------
echo "[PHASE 1] INSTALL BUILD DEPENDENCIES"
sudo apt update
sudo apt install -y \
  live-build debootstrap squashfs-tools xorriso \
  ca-certificates gnupg git \
  dpkg-dev fakeroot \
  minisign || true

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
RELEASEDIR="$WORKDIR/release"
mkdir -p "$WORKDIR" "$RELEASEDIR"
cd "$WORKDIR"

sudo lb clean --purge || true
sudo rm -rf .build cache config auto || true
pause

# -------------------------------------------------
# PHASE 3: Sentinel repository bootstrap (Iteration 2)
# -------------------------------------------------
echo "[PHASE 3] SENTINEL REPOSITORY BOOTSTRAP"

mkdir -p config/hooks/normal
cat > config/hooks/normal/010-sentinel-repo.hook.chroot <<EOF
#!/bin/sh
set -eu

# Install Sentinel keyring (must be present in Debian or preseeded mirror)
apt-get update
apt-get install -y ${SENTINEL_KEYRING_PKG}

# Configure Sentinel APT repository
install -d /etc/apt/sources.list.d
cat > /etc/apt/sources.list.d/sentinel.list <<SRC
deb [signed-by=/usr/share/keyrings/sentinel-archive-keyring.gpg] \
${SENTINEL_REPO_URL} ${SENTINEL_DIST} ${SENTINEL_REPO_COMPONENT}
SRC

apt-get update
EOF
chmod +x config/hooks/normal/010-sentinel-repo.hook.chroot
pause

# -------------------------------------------------
# PHASE 4: live-build config
# -------------------------------------------------
echo "[PHASE 4] CONFIGURING LIVE-BUILD"

sudo lb config \
  --distribution "$SENTINEL_DIST" \
  --architectures "$SENTINEL_ARCH" \
  --binary-images iso-hybrid \
  --bootloaders "grub-pc grub-efi" \
  --linux-flavours amd64 \
  --linux-packages "linux-image" \
  --debian-installer live \
  --debian-installer-gui true \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components quiet splash live-media-path=/live" \
  --iso-volume "Sentinel OS v${SENTINEL_VERSION}" \
  --iso-application "Sentinel OS" \
  --iso-publisher "Sentinel OS Project" \
  --apt-recommends false

sudo chown -R "$USER:$USER" config
pause

# -------------------------------------------------
# PHASE 4.1: Filesystem + branding scaffolding
# -------------------------------------------------
echo "[PHASE 4.1] FILESYSTEM + BRANDING"
mkdir -p \
  config/includes.chroot/usr/share/backgrounds/sentinel \
  config/includes.chroot/usr/share/icons/sentinel \
  config/includes.chroot/usr/share/themes/sentinel \
  config/includes.chroot/etc/dconf/db/local.d \
  config/includes.chroot/etc/dconf/profile
pause

# -------------------------------------------------
# PHASE 5: Package lists (Iteration 2 compliant)
# -------------------------------------------------
echo "[PHASE 5] PACKAGE LISTS (REPO-BASED)"
mkdir -p config/package-lists

cat > config/package-lists/10-desktop-mate-base.list.chroot <<'EOF'
mate-desktop-environment-core
lightdm
lightdm-gtk-greeter
network-manager
network-manager-gnome
policykit-1
sudo
firefox-esr
ca-certificates
gnupg
curl
wget
git
jq
python3
EOF

cat > config/package-lists/20-sentinel-base-security.list.chroot <<'EOF'
live-boot
live-config
live-tools
firmware-linux
firmware-linux-nonfree
firmware-misc-nonfree
linux-image-amd64
xorg
xserver-xorg-core
xserver-xorg-input-all
xserver-xorg-video-all
apparmor
apparmor-utils
apparmor-profiles
unattended-upgrades
chrony
needrestart
nftables

# Sentinel policy packages (from Sentinel repo)
sentinel-release
sentinel-hardening
sentinel-firewall
EOF
pause

# -------------------------------------------------
# PHASE 6: Live user policy
# -------------------------------------------------
echo "[PHASE 6] LIVE USER POLICY"

mkdir -p config/includes.chroot/etc/live
cat > config/includes.chroot/etc/live/config.conf <<'EOF'
LIVE_USER="user"
LIVE_USER_FULLNAME="Sentinel Live"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev"
LIVE_USER_PASSWORD=""
EOF

mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
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
else
  passwd -l user >/dev/null 2>&1 || true
fi
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh

mkdir -p config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/etc/systemd/system/sentinel-live-guard.service <<'EOF'
[Unit]
Description=Sentinel Live Guard
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sentinel-live-guard.sh

[Install]
WantedBy=multi-user.target
EOF
pause

# -------------------------------------------------
# PHASE 7: Live warning banner
# -------------------------------------------------
echo "[PHASE 7] LIVE WARNING BANNER"
cat > config/includes.chroot/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

cat > config/includes.chroot/etc/dconf/db/local.d/00-sentinel-live-warning <<'EOF'
[org/mate/panel/objects/clock]
format='SENTINEL LIVE – NOT A SECURE INSTALL | %a %d %b %H:%M'
EOF
pause

# -------------------------------------------------
# PHASE 8: Enable services
# -------------------------------------------------
echo "[PHASE 8] ENABLE SERVICES"
mkdir -p config/hooks/normal
cat > config/hooks/normal/090-enable-sentinel.hook.chroot <<'EOF'
#!/bin/sh
set -eu
systemctl enable sentinel-live-guard.service || true
systemctl enable sentinel-nftables.service || true
systemctl enable apparmor.service || true
systemctl enable unattended-upgrades.service || true
dconf update || true
EOF
chmod +x config/hooks/normal/090-enable-sentinel.hook.chroot
pause

# -------------------------------------------------
# PHASE 9: Build ISO
# -------------------------------------------------
echo "[PHASE 9] BUILDING ISO"
sudo lb clean --purge
sudo lb build 2>&1 | tee "$WORKDIR/build.log"

ISO="$(ls *.iso | head -n1)"
[ -n "$ISO" ] || die "ISO not produced"

FINAL_ISO="Sentinel-OS-v${SENTINEL_VERSION}-${SENTINEL_DIST}-${SENTINEL_ARCH}.iso"
mv "$ISO" "$FINAL_ISO"
sha256sum "$FINAL_ISO" > "$FINAL_ISO.sha256"

# -------------------------------------------------
# PHASE 10: Release artifacts (Iteration 3)
# -------------------------------------------------
echo "[PHASE 10] RELEASE ARTIFACTS"

cp "$FINAL_ISO"* "$RELEASEDIR/"

{
  echo "sentinel_version=${SENTINEL_VERSION}"
  echo "build_date_utc=$(date -u +%FT%TZ)"
  echo "debian_release=${SENTINEL_DIST}"
  echo "architecture=${SENTINEL_ARCH}"
} > "$RELEASEDIR/build-info.txt"

if command -v minisign >/dev/null 2>&1; then
  minisign -Sm "$RELEASEDIR/$FINAL_ISO"
  minisign -Sm "$RELEASEDIR/$FINAL_ISO.sha256"
fi

echo "[+] Release complete:"
ls -lh "$RELEASEDIR"