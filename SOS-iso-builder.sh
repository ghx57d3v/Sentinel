#!/usr/bin/env bash
# Sentinel OS v1 ISO Build Script (Debian 12 Bookworm, amd64, MATE)
#
# Goals (v1):
# - Bare-metal installable ISO (live + installer)
# - Base hardening applied on installed system via Sentinel "policy packages"
# - Live session is convenience-only: non-admin, no default password, optional autologin
# - Secure Boot deferred

set -euo pipefail

pause() { read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."; }
die() { echo "[!] $*" >&2; exit 1; }

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  die "Do not run as root. Run as a normal user with sudo."
fi

echo "=== Sentinel OS v1 ISO Build ==="

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
  live-build debootstrap squashfs-tools xorriso \
  ca-certificates gnupg git \
  dpkg-dev fakeroot

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
sudo rm -rf .build cache config auto local-packages || true
mkdir -p local-packages
pause

# -------------------------------------------------
# PHASE 3: Build Sentinel policy packages (host-side)
# -------------------------------------------------
echo "[PHASE 3] BUILDING SENTINEL POLICY PACKAGES (.deb)"
build_deb() {
  local pkg="$1" ver="$2" root="$3"
  mkdir -p "$root/DEBIAN"
  fakeroot dpkg-deb --build "$root" "local-packages/${pkg}_${ver}_all.deb" >/dev/null
}

# sentinel-release: OS identity + apt pinning (minimal)
rm -rf /tmp/sentinel-release
mkdir -p /tmp/sentinel-release/{DEBIAN,etc/os-release.d,etc/apt/preferences.d}
cat > /tmp/sentinel-release/DEBIAN/control <<'EOF'
Package: sentinel-release
Version: 1.0.0
Section: misc
Priority: optional
Architecture: all
Maintainer: Sentinel OS Project
Description: Sentinel OS identity and repository policy
EOF

# Minimal identity (doesn't replace /etc/os-release; provides supplemental file)
cat > /tmp/sentinel-release/etc/os-release.d/sentinel.conf <<'EOF'
SENTINEL_OS=1
SENTINEL_CODENAME=bookworm
EOF

# Pin strictly to stable + security + updates; prevents accidental testing/unstable pulls
cat > /tmp/sentinel-release/etc/apt/preferences.d/99-sentinel-pin <<'EOF'
Package: *
Pin: release a=stable
Pin-Priority: 700

Package: *
Pin: release a=stable-security
Pin-Priority: 800

Package: *
Pin: release a=stable-updates
Pin-Priority: 650

Package: *
Pin: release a=testing
Pin-Priority: -10

Package: *
Pin: release a=unstable
Pin-Priority: -10
EOF

build_deb "sentinel-release" "1.0.0" "/tmp/sentinel-release"

# sentinel-firewall: nftables baseline rules + enable service
rm -rf /tmp/sentinel-firewall
mkdir -p /tmp/sentinel-firewall/{DEBIAN,etc/nftables.d,etc/systemd/system}
cat > /tmp/sentinel-firewall/DEBIAN/control <<'EOF'
Package: sentinel-firewall
Version: 1.0.0
Section: admin
Priority: optional
Architecture: all
Maintainer: Sentinel OS Project
Depends: nftables
Description: Sentinel OS baseline nftables firewall policy
EOF

cat > /tmp/sentinel-firewall/etc/nftables.d/sentinel.nft <<'EOF'
# Sentinel baseline: deny inbound, allow outbound
table inet sentinel {
  chain input {
    type filter hook input priority 0; policy drop;

    ct state established,related accept
    iif "lo" accept

    # ICMP/ICMPv6 for basic network functionality (ping, ND)
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

    # Optional: allow DHCP client traffic
    udp sport 67 udp dport 68 accept
    udp sport 547 udp dport 546 accept

    # Log remaining drops (rate-limited)
    limit rate 10/second burst 20 packets log prefix "SENTINEL_DROP_IN: " flags all counter drop
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF

cat > /tmp/sentinel-firewall/etc/systemd/system/sentinel-nftables.service <<'EOF'
[Unit]
Description=Sentinel nftables policy
Wants=network-pre.target
Before=network-pre.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /tmp/sentinel-firewall/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -eu
# Ensure /etc/nftables.conf includes our policy
if [ ! -f /etc/nftables.conf ] || ! grep -q 'table inet sentinel' /etc/nftables.conf 2>/dev/null; then
  cat >/etc/nftables.conf <<'CONF'
#!/usr/sbin/nft -f
flush ruleset
include "/etc/nftables.d/*.nft"
CONF
fi
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable sentinel-nftables.service >/dev/null 2>&1 || true
EOF
chmod +x /tmp/sentinel-firewall/DEBIAN/postinst

build_deb "sentinel-firewall" "1.0.0" "/tmp/sentinel-firewall"

# sentinel-hardening: sysctl + apparmor + unattended upgrades + disable noisy services
rm -rf /tmp/sentinel-hardening
mkdir -p /tmp/sentinel-hardening/{DEBIAN,etc/sysctl.d,etc/apt/apt.conf.d,etc/systemd/journald.conf.d}
cat > /tmp/sentinel-hardening/DEBIAN/control <<'EOF'
Package: sentinel-hardening
Version: 1.0.0
Section: admin
Priority: optional
Architecture: all
Maintainer: Sentinel OS Project
Depends: apparmor, apparmor-utils, unattended-upgrades
Description: Sentinel OS base hardening policy (conservative)
EOF

cat > /tmp/sentinel-hardening/etc/sysctl.d/99-sentinel.conf <<'EOF'
# Sentinel conservative hardening
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

# Enable unattended-upgrades for security by default
cat > /tmp/sentinel-hardening/etc/apt/apt.conf.d/20auto-upgrades-sentinel <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Persistent journald logs
cat > /tmp/sentinel-hardening/etc/systemd/journald.conf.d/00-sentinel.conf <<'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=1G
EOF

cat > /tmp/sentinel-hardening/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -eu

# Apply sysctl (best-effort)
sysctl --system >/dev/null 2>&1 || true

# AppArmor enforcing (best-effort)
systemctl enable apparmor.service >/dev/null 2>&1 || true
systemctl start apparmor.service >/dev/null 2>&1 || true

# Turn off common discovery services if present (best-effort)
systemctl disable --now avahi-daemon.service >/dev/null 2>&1 || true
systemctl disable --now bluetooth.service >/dev/null 2>&1 || true

# Needrestart is optional; don't force prompts here

EOF
chmod +x /tmp/sentinel-hardening/DEBIAN/postinst

build_deb "sentinel-hardening" "1.0.0" "/tmp/sentinel-hardening"

pause

# -------------------------------------------------
# PHASE 4: live-build config
# -------------------------------------------------
echo "[PHASE 4] CONFIGURING LIVE-BUILD"

sudo lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloaders "grub-pc grub-efi" \
  --linux-flavours amd64 \
  --linux-packages "linux-image" \
  --debian-installer live \
  --debian-installer-gui true \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components quiet splash live-media-path=/live" \
  --iso-volume "Sentinel OS v1" \
  --iso-application "Sentinel OS" \
  --iso-publisher "Sentinel OS Project" \
  --apt-recommends false

sudo chown -R "$USER:$USER" config
pause

echo "[PHASE 4.1] APT + DESKTOP FILESYSTEM SETUP"

mkdir -p config/archives
mkdir -p config/includes.chroot/etc/apt/apt.conf.d

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
# PHASE 5: Include local Sentinel packages
# -------------------------------------------------
echo "[PHASE 5] ADDING LOCAL SENTINEL PACKAGES"
mkdir -p config/packages.chroot
cp -f local-packages/*.deb config/packages.chroot/
pause

# -------------------------------------------------
# PHASE 6: Package lists (BASE only; keep minimal)
# -------------------------------------------------
echo "[PHASE 6] PACKAGE LISTS (BASE MINIMAL)"
mkdir -p config/package-lists

cat > config/package-lists/10-desktop-mate-base.list.chroot <<'EOF'
# Minimal MATE base
mate-desktop-environment-core
lightdm
lightdm-gtk-greeter

# Network + basics
network-manager
network-manager-gnome
policykit-1
sudo

# Browser (one)
firefox-esr

# Essentials
ca-certificates
gnupg
curl
wget
git
jq
python3
EOF

cat > config/package-lists/20-sentinel-base-security.list.chroot <<'EOF'
# Live system
live-boot
live-config
live-tools

# Firmware / hardware support
firmware-linux
firmware-linux-nonfree
firmware-misc-nonfree

# Kernel (meta)
linux-image-amd64

# Xorg + common drivers (bare-metal focused; still broadly compatible)
xorg
xserver-xorg-core
xserver-xorg-input-all
xserver-xorg-video-all

# Baseline security components (Sentinel policy packages depend on some)
apparmor
apparmor-utils
apparmor-profiles
unattended-upgrades
chrony
needrestart
nftables

# Sentinel policy packages (local .deb)
sentinel-release
sentinel-hardening
sentinel-firewall
EOF
pause

# -------------------------------------------------
# PHASE 7: Live user policy (convenience-only, non-admin, no password)
# -------------------------------------------------
echo "[PHASE 7] LIVE USER + LIGHTDM (LIVE ONLY)"

mkdir -p config/includes.chroot/etc/live
cat > config/includes.chroot/etc/live/config.conf <<'EOF'
LIVE_USER="user"
LIVE_USER_FULLNAME="Sentinel Live"
# Live user is NOT admin. No sudo group.
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev"
# Do not set a known password.
LIVE_USER_PASSWORD=""
EOF

mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-sentinel.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

# Live autologin is allowed for convenience, but guarded to not persist post-install.
cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/60-sentinel-live-autologin.conf <<'EOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
EOF

# Guard: remove live autologin on installed systems; also lock live user password in live.
mkdir -p config/includes.chroot/usr/local/sbin
cat > config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh <<'EOF'
#!/bin/sh
set -eu

# If not booted as live, ensure autologin is removed
if ! grep -q 'boot=live' /proc/cmdline 2>/dev/null; then
  rm -f /etc/lightdm/lightdm.conf.d/60-sentinel-live-autologin.conf
  exit 0
fi

# Live session: lock the live user password if user exists (best-effort)
if id user >/dev/null 2>&1; then
  passwd -l user >/dev/null 2>&1 || true
fi
EOF
chmod +x config/includes.chroot/usr/local/sbin/sentinel-live-guard.sh

mkdir -p config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/etc/systemd/system/sentinel-live-guard.service <<'EOF'
[Unit]
Description=Sentinel Live Guard (autologin + live user lock)
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
# PHASE 8: Visible Live warning banner (dconf default)
# -------------------------------------------------
echo "[PHASE 8] LIVE WARNING BANNER (DESKTOP)"

mkdir -p config/includes.chroot/etc/dconf/profile
cat > config/includes.chroot/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

mkdir -p config/includes.chroot/etc/dconf/db/local.d
cat > config/includes.chroot/etc/dconf/db/local.d/00-sentinel-live-warning <<'EOF'
# MATE: set a clear warning in the panel clock format (simple, visible)
[org/mate/panel/objects/clock]
format='SENTINEL LIVE – NOT A SECURE INSTALL | %a %d %b %H:%M'
EOF
pause

# -------------------------------------------------
# PHASE 9: Enable services (via systemctl in hook; owned by packages where possible)
# -------------------------------------------------
echo "[PHASE 9] ENABLE SERVICES (CHROOT HOOK)"
mkdir -p config/hooks/normal
cat > config/hooks/normal/090-enable-sentinel.hook.chroot <<'EOF'
#!/bin/sh
set -eu

# Enable live guard
systemctl enable sentinel-live-guard.service >/dev/null 2>&1 || true

# Enable Sentinel firewall and AppArmor (policy packages should do this too; belt-and-suspenders)
systemctl enable sentinel-nftables.service >/dev/null 2>&1 || true
systemctl enable apparmor.service >/dev/null 2>&1 || true

# Enable unattended upgrades timer/services (package provides config; enabling may vary)
systemctl enable unattended-upgrades.service >/dev/null 2>&1 || true

# Update dconf defaults
if command -v dconf >/dev/null 2>&1; then
  dconf update >/dev/null 2>&1 || true
fi
EOF
chmod +x config/hooks/normal/090-enable-sentinel.hook.chroot
pause

# -------------------------------------------------
# PHASE 10: Build ISO
# -------------------------------------------------
echo "[PHASE 10] BUILDING ISO"
sudo lb clean --purge
sudo lb build 2>&1 | tee "$WORKDIR/build.log"

ISO_FOUND="$(ls -1 *.iso 2>/dev/null | head -n1 || true)"
[ -n "$ISO_FOUND" ] || die "No ISO produced."

ISO_DST="Sentinel-OS-v1.0.0-bookworm-amd64.iso"
mv "$ISO_FOUND" "$ISO_DST"
sha256sum "$ISO_DST" > "$ISO_DST.sha256"

echo "[+] Built:"
ls -lh "$ISO_DST" "$ISO_DST.sha256"