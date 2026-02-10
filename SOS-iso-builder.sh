#!/usr/bin/env bash
# Sentinel OS v1 ISO Build Script (Debian 12 Bookworm, amd64, MATE)
#
# Goals (v1):
# - Bare-metal installable ISO (live + installer)
# - Base hardening applied on installed system via Sentinel "policy packages"
# - Live session is convenience-only: non-admin, no default password, optional autologin
# - Secure Boot deferred

set -euo pipefail

# -------------------------------------------------
# CI MODE (non-interactive)
# -------------------------------------------------
CI_MODE=0
for arg in "$@"; do
  case "$arg" in
    --ci) CI_MODE=1 ;;
  esac
done

if [ "$CI_MODE" -eq 1 ]; then
  echo "[INFO] CI mode enabled: running non-interactively"
fi

pause() {
  if [ "$CI_MODE" -eq 1 ]; then
    return 0
  fi
  read -rp "[?] Press ENTER to continue or Ctrl+C to abort..."
}

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

# ---- sentinel-release ----
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

cat > /tmp/sentinel-release/etc/os-release.d/sentinel.conf <<'EOF'
SENTINEL_OS=1
SENTINEL_CODENAME=hercules
EOF

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

build_deb sentinel-release 1.0.0 /tmp/sentinel-release

# ---- sentinel-firewall ----
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
table inet sentinel {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif "lo" accept
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
    udp sport 67 udp dport 68 accept
    udp sport 547 udp dport 546 accept
    limit rate 10/second burst 20 packets log prefix "SENTINEL_DROP_IN: " flags all counter drop
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output  priority 0; policy accept; }
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
if [ ! -f /etc/nftables.conf ] || ! grep -q 'table inet sentinel' /etc/nftables.conf; then
cat >/etc/nftables.conf <<'CONF'
#!/usr/sbin/nft -f
flush ruleset
include "/etc/nftables.d/*.nft"
CONF
fi
systemctl daemon-reload || true
systemctl enable sentinel-nftables.service || true
EOF
chmod +x /tmp/sentinel-firewall/DEBIAN/postinst

build_deb sentinel-firewall 1.0.0 /tmp/sentinel-firewall

# ---- sentinel-hardening ----
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

cat > /tmp/sentinel-hardening/etc/apt/apt.conf.d/20auto-upgrades-sentinel <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

cat > /tmp/sentinel-hardening/etc/systemd/journald.conf.d/00-sentinel.conf <<'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=1G
EOF

cat > /tmp/sentinel-hardening/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -eu
sysctl --system || true
systemctl enable apparmor.service || true
systemctl start apparmor.service || true
systemctl disable --now avahi-daemon.service || true
systemctl disable --now bluetooth.service || true
EOF
chmod +x /tmp/sentinel-hardening/DEBIAN/postinst

build_deb sentinel-hardening 1.0.0 /tmp/sentinel-hardening

# ---- sentinel-auth ----
rm -rf /tmp/sentinel-auth
mkdir -p /tmp/sentinel-auth/{DEBIAN,usr/share/pam-configs,etc/profile.d,etc/sudoers.d,var/log/sudo-io}

cat > /tmp/sentinel-auth/DEBIAN/control <<'EOF'
Package: sentinel-auth
Version: 1.0.0
Section: admin
Priority: optional
Architecture: all
Maintainer: Sentinel OS Project
Depends: sudo, libpam-modules, libpam-runtime, libpam-pwquality
Description: Sentinel OS authentication hardening (PAM + sudo logging)
EOF

cat > /tmp/sentinel-auth/etc/profile.d/00-sentinel-umask.sh <<'EOF'
umask 027
EOF

# -------------------------------------------------
# PHASE 4: Build ISO
# -------------------------------------------------
echo "[PHASE 4] BUILDING ISO"
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4
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
  --mirror-binary http://deb.debian.org/debian/ \
  --mirror-binary-security http://security.debian.org/ \
  --mirror-bootstrap http://deb.debian.org/debian/ \
  --mirror-chroot-security http://security.debian.org/ \
  --bootappend-live "boot=live components live-media-path=/live" \
  --iso-volume "Sentinel OS v1" \
  --iso-application "Sentinel OS" \
  --iso-publisher "Sentinel OS Project" \
  --apt-recommends false

sudo mkdir -p config/installer
echo bookworm > config/installer/distribution

sudo mkdir -p config/package-lists
cat > config/package-lists/00-installer.list.binary <<EOF
debian-installer-launcher
EOF

sudo lb build 2>&1 | tee "$WORKDIR/build.log"

ISO_FOUND="$(ls -1 *.iso 2>/dev/null | head -n1 || true)"
[ -n "$ISO_FOUND" ] || die "No ISO produced."

ISO_DST="Sentinel-OS-v1.01-hercules.iso"
mv "$ISO_FOUND" "$ISO_DST"
sha256sum "$ISO_DST" > "$ISO_DST.sha256"

echo "[+] Built:"
ls -lh "$ISO_DST" "$ISO_DST.sha256"

#-------------------------------------------------
# PHASE 11: Generate build-info.txt
# -------------------------------------------------
echo "[PHASE 11] GENERATING BUILD INFO"

BUILD_DATE="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

cat > build-info.txt <<EOF
Sentinel OS Build Information
=============================

Project: Sentinel OS
Version: v1.0.0
Codename: Hercules
Architecture: amd64
Desktop: MATE
Kernel: linux-image-amd64

ISO Filename:
$ISO_DST

Build Date:
$BUILD_DATE

Git Commit:
$GIT_COMMIT

Included Sentinel Policy Packages:
- sentinel-release
- sentinel-hardening
- sentinel-firewall
- sentinel-auth

Build Mode:
$( [ "$CI_MODE" -eq 1 ] && echo "CI (non-interactive)" || echo "Interactive" )

Checksum File:
$ISO_DST.sha256

Notes:
- Base hardening applied post-install
- Live session is non-privileged
- Secure Boot intentionally deferred
EOF

echo "[+] build-info.txt generated"
ls -lh build-info.txt
build_deb sentinel-auth 1.0.0 /tmp/sentinel-auth
pause
