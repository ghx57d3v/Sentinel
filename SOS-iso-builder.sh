#!/usr/bin/env bash
# Sentinel OS v1.0 (MINIMAL) ISO Build Script
# Debian 12 (Bookworm) amd64 | live-build compatible
#
# Goals:
# - Build a bootable, installable Debian live ISO with MATE
# - Minimal, solid baseline (no external tooling profiles, no vendor binaries)
# - Live session boots to GUI reliably in common hypervisors
# - Hardening is applied on FIRST BOOT of INSTALLED system only (never on live boots)
#
# Notes on reproducibility:
# - This uses standard Debian mirrors by default (not deterministic across time).
# - For deterministic builds, point the sources to a fixed snapshot mirror you control.

set -euo pipefail

pause() { read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."; }
die() { echo "[!] $*" >&2; exit 1; }

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  die "Do not run as root. Run as a normal user with sudo."
fi

echo "=== Sentinel OS v1.0 (MINIMAL) ISO Build ==="

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
  live-build debootstrap squashfs-tools xorriso git ca-certificates gnupg

if ! groups | grep -q '\bsudo\b'; then
  sudo usermod -aG sudo "$USER"
  echo "[!] Added $USER to sudo group. Log out/in and re-run."
  exit 0
fi

# Ensure debootstrap is discoverable (some PATH edge cases)
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
# - iso-hybrid for USB booting
# - grub-efi for UEFI (and BIOS via hybrid)
# - debian-installer live for installable ISO

sudo lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloader grub-efi \
  --debian-installer live \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components" \
  --iso-volume "Sentinel OS 1.0" \
  --iso-application "Sentinel OS" \
  --iso-publisher "Sentinel OS Project" \
  --apt-recommends false

# live-build creates root-owned config; fix for subsequent writes
sudo chown -R "$USER:$USER" config
pause

# -------------------------------------------------
# PHASE 4: APT sources + policy (chroot)
# -------------------------------------------------
echo "[PHASE 4] WRITING APT SOURCES + POLICY"
mkdir -p config/archives

cat > config/archives/bookworm.list.chroot <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

mkdir -p config/includes.chroot/etc/apt/apt.conf.d
cat > config/includes.chroot/etc/apt/apt.conf.d/90-sentinel <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
pause

# -------------------------------------------------
# PHASE 5: Package lists (minimal, Bookworm-valid)
# -------------------------------------------------
echo "[PHASE 5] WRITING PACKAGE LISTS"
mkdir -p config/package-lists

# Desktop: MATE + LightDM + NetworkManager
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

# Core: live support + VM-friendly graphics + baseline security
cat > config/package-lists/20-sentinel-core.list.chroot <<'EOF'
# --- Live boot plumbing ---
live-boot
live-config
live-tools

# --- Kernel ---
linux-image-amd64

# --- X / graphics (VM-friendly) ---
xorg
xserver-xorg-core
xserver-xorg-input-all
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xserver-xorg-video-qxl
spice-vdagent
qemu-guest-agent

# --- Baseline security (minimal + solid) ---
apparmor
apparmor-utils
apparmor-profiles
ufw
unattended-upgrades
needrestart
chrony

# --- Essentials ---
ca-certificates
gnupg
curl
wget
git
jq
python3
EOF
pause

# -------------------------------------------------
# PHASE 6: Live user + LightDM autologin (live-only)
# -------------------------------------------------
echo "[PHASE 6] CONFIGURING LIVE USER + LIGHTDM"

# live-config will create the user automatically.
mkdir -p config/includes.chroot/etc/live
cat > config/includes.chroot/etc/live/config.conf <<'EOF'
LIVE_USERNAME="user"
LIVE_USER_FULLNAME="Sentinel Live"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev sudo"
LIVE_USER_NO_PASSWORD="true"
EOF

# LightDM defaults (MATE session)
mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

# Autologin config present in image, but removed on non-live boots by guard service
cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/60-sentinel-live-autologin.conf <<'EOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
EOF

# Live autologin guard: if NOT boot=live, remove autologin file before display-manager starts
mkdir -p config/includes.chroot/usr/local/sbin
cat > config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh <<'EOF'
#!/bin/sh
set -eu
if ! grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  rm -f /etc/lightdm/lightdm.conf.d/60-sentinel-live-autologin.conf
fi
exit 0
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
# PHASE 7: Baseline hardening (files only)
# -------------------------------------------------
echo "[PHASE 7] BASELINE HARDENING (FILES ONLY)"
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
echo "[PHASE 8] FIRST-BOOT HARDENING (INSTALLED SYSTEM ONLY)"

cat > config/includes.chroot/usr/local/sbin/sentinel-firstboot.sh <<'EOF'
#!/bin/sh
set -eu

# Never run in LIVE environment.
if grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  exit 0
fi

LOG="/var/log/sentinel-firstboot.log"
MARK="/var/lib/sentinel-firstboot.done"

mkdir -p /var/lib
if [ -f "$MARK" ]; then
  exit 0
fi

echo "[Sentinel] First boot hardening started" >> "$LOG" || true

# Apply sysctl now
sysctl --system >> "$LOG" 2>&1 || true

# Firewall defaults + enable
if command -v ufw >/dev/null 2>&1; then
  ufw default deny incoming >> "$LOG" 2>&1 || true
  ufw default allow outgoing >> "$LOG" 2>&1 || true
  ufw --force enable >> "$LOG" 2>&1 || true
fi

# Ensure AppArmor is enabled + running
systemctl enable apparmor.service >> "$LOG" 2>&1 || true
systemctl start  apparmor.service >> "$LOG" 2>&1 || true

# Reduce common desktop attack surface (installed system)
systemctl disable avahi-daemon.service >> "$LOG" 2>&1 || true
systemctl disable bluetooth.service >> "$LOG" 2>&1 || true

touch "$MARK"
echo "[Sentinel] First boot hardening completed" >> "$LOG" || true

# Self-disable
systemctl disable sentinel-firstboot.service >> "$LOG" 2>&1 || true
exit 0
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
# PHASE 9: Enable minimal services deterministically (idempotent hook)
# -------------------------------------------------
echo "[PHASE 9] ENABLING SERVICES (DETERMINISTIC)"
mkdir -p config/hooks/normal

cat > config/hooks/normal/090-enable-services.hook.chroot <<'EOF'
#!/bin/sh
set -eu

# Enable guard + firstboot by creating the wants symlinks.
mkdir -p /etc/systemd/system/multi-user.target.wants

ln -sf /etc/systemd/system/sentinel-live-guard.service \
  /etc/systemd/system/multi-user.target.wants/sentinel-live-guard.service

ln -sf /etc/systemd/system/sentinel-firstboot.service \
  /etc/systemd/system/multi-user.target.wants/sentinel-firstboot.service

exit 0
EOF
chmod +x config/hooks/normal/090-enable-services.hook.chroot
pause

# -------------------------------------------------
# PHASE 10: Build ISO + checksum
# -------------------------------------------------
echo "[PHASE 10] BUILDING ISO"
sudo lb clean
sudo lb build 2>&1 | tee "$WORKDIR/build.log"

echo "[+] Build complete. ISO output(s):"
ls -lh ./*.iso || true

ISO_FOUND="$(ls -1 ./*.iso 2>/dev/null | head -n 1 || true)"
[ -n "$ISO_FOUND" ] || die "No ISO file found after build."

ISO_DST="Sentinel-OS-v1.0-amd64.iso"
mv "$ISO_FOUND" "$ISO_DST"
sha256sum "$ISO_DST" > "$ISO_DST.sha256"

echo "[+] Artifacts:"
ls -lh "$ISO_DST" "$ISO_DST.sha256"
echo "[+] Verify with: sha256sum -c $ISO_DST.sha256"

