#!/usr/bin/env bash
# Sentinel OS v1.9 ISO Build
# Adds:
# - Automatic download of theme 1627601 (best-effort, non-fatal if it fails)
# - Sentinel Papirus icon variant
# - Default theme + icons applied

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

echo "=== Sentinel OS v1.9 ISO Build (Theme auto-download enabled) ==="

sudo apt update
sudo apt install -y live-build debootstrap squashfs-tools xorriso git \
ca-certificates gnupg papirus-icon-theme wget unzip

WORKDIR="$HOME/sentinel-iso"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

sudo lb clean --purge || true
rm -rf .build cache || true

sudo lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloader grub-efi \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components" \
  --apt-recommends false

sudo chown -R "$USER:$USER" config

mkdir -p config/package-lists

cat <<'EOF' > config/package-lists/mate.list.chroot
mate-desktop-environment
lightdm
lightdm-gtk-greeter
network-manager
network-manager-gnome
sudo
zenity
papirus-icon-theme
EOF

mkdir -p config/hooks/normal

cat <<'EOF' > config/hooks/normal/085-install-sentinel-theme.hook.chroot
#!/bin/sh
set -eu

THEME_DIR="/usr/share/themes"
DEST="$THEME_DIR/Sentinel-1627601"

if [ -d "$DEST" ]; then
  exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

echo "[Sentinel] Attempting to download theme 1627601..."

if wget -O theme.zip "https://www.mate-look.org/p/1627601/loadFiles" ; then
  unzip theme.zip || true
  FOUND_FILE=$(find . -maxdepth 4 -type f -name "index.theme" | head -n1 || true)
  if [ -n "$FOUND_FILE" ]; then
    FOUND_DIR=$(dirname "$FOUND_FILE")
    cp -r "$FOUND_DIR" "$DEST"
    echo "[Sentinel] Theme installed."
  else
    echo "[Sentinel] Theme archive downloaded but folder not detected."
  fi
else
  echo "[Sentinel] Theme download failed. Falling back to default theme."
fi
EOF

chmod +x config/hooks/normal/085-install-sentinel-theme.hook.chroot

cat <<'EOF' > config/hooks/normal/090-build-sentinel-icons.hook.chroot
#!/bin/sh
set -eu

ICON_SRC="/usr/share/icons/Papirus-Dark"
ICON_DST="/usr/share/icons/Sentinel-Papirus"

if [ ! -d "$ICON_DST" ]; then
  cp -r "$ICON_SRC" "$ICON_DST"
fi

sed -i 's/^Name=.*/Name=Sentinel Papirus/' "$ICON_DST/index.theme" || true

find "$ICON_DST" -type f -name "*.svg" -exec sed -i \
  -e 's/#5c616c/#FFC800/g' \
  -e 's/#6c727d/#FFC800/g' \
  -e 's/#4f4f4f/#FFC800/g' {} +

gtk-update-icon-cache "$ICON_DST" || true
EOF

chmod +x config/hooks/normal/090-build-sentinel-icons.hook.chroot

mkdir -p config/includes.chroot/etc/skel/.config

cat <<'EOF' > config/includes.chroot/etc/skel/.config/sentinel-theme.sh
#!/bin/sh
gsettings set org.mate.interface gtk-theme "Sentinel-1627601" || true
gsettings set org.mate.interface icon-theme "Sentinel-Papirus" || true
gsettings set org.mate.Marco.general theme "Sentinel-1627601" || true
EOF


# System-wide defaults via dconf (applies to new users, including live user)
mkdir -p config/includes.chroot/etc/dconf/profile
cat <<'EOF' > config/includes.chroot/etc/dconf/profile/user
user-db:user
system-db:local
EOF

mkdir -p config/includes.chroot/etc/dconf/db/local.d
cat <<'EOF' > config/includes.chroot/etc/dconf/db/local.d/00-sentinel-theme
[org/mate/interface]
gtk-theme='Sentinel-1627601'
icon-theme='Sentinel-Papirus'

[org/mate/Marco/general]
theme='Sentinel-1627601'
EOF

# One-time per-user apply (helps if dconf defaults don't land for any reason)
mkdir -p config/includes.chroot/usr/local/bin
cat <<'EOF' > config/includes.chroot/usr/local/bin/sentinel-apply-theme
#!/bin/sh
set -eu

MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/.sentinel-theme-applied"
[ -f "$MARKER" ] && exit 0

# Best-effort: only run if gsettings is available and a session bus exists
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.mate.interface gtk-theme "Sentinel-1627601" 2>/dev/null || true
  gsettings set org.mate.interface icon-theme "Sentinel-Papirus" 2>/dev/null || true
  gsettings set org.mate.Marco.general theme "Sentinel-1627601" 2>/dev/null || true
fi

mkdir -p "$(dirname "$MARKER")"
: > "$MARKER"
EOF
chmod +x config/includes.chroot/usr/local/bin/sentinel-apply-theme

mkdir -p config/includes.chroot/etc/xdg/autostart
cat <<'EOF' > config/includes.chroot/etc/xdg/autostart/sentinel-apply-theme.desktop
[Desktop Entry]
Type=Application
Name=Sentinel Theme Apply
Exec=/usr/local/bin/sentinel-apply-theme#!/usr/bin/env bash
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


OnlyShowIn=MATE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

# Ensure dconf database is compiled inside chroot
cat <<'EOF' > config/hooks/normal/095-dconf-update.hook.chroot
#!/bin/sh
set -eu
command -v dconf >/dev/null 2>&1 || exit 0
dconf update || true
EOF
chmod +x config/hooks/normal/095-dconf-update.hook.chroot

sudo lb build 2>&1 | tee "$WORKDIR/build.log"

echo "Build finished. Check the ISO in $WORKDIR"
