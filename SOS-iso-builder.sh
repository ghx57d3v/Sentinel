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

cat > /tmp/sentinel-release/etc/os-release.d/sentinel.conf <<'EOF'
SENTINEL_OS=1
SENTINEL_CODENAME=bookworm
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

    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

    udp sport 67 udp dport 68 accept
    udp sport 547 udp dport 546 accept

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
sysctl --system >/dev/null 2>&1 || true
systemctl enable apparmor.service >/dev/null 2>&1 || true
systemctl start apparmor.service >/dev/null 2>&1 || true
systemctl disable --now avahi-daemon.service >/dev/null 2>&1 || true
systemctl disable --now bluetooth.service >/dev/null 2>&1 || true
EOF
chmod +x /tmp/sentinel-hardening/DEBIAN/postinst

build_deb "sentinel-hardening" "1.0.0" "/tmp/sentinel-hardening"

# sentinel-auth: PAM + sudo logging (NEW)
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

cat > /tmp/sentinel-auth/usr/share/pam-configs/sentinel-faillock <<'EOF'
Name: Sentinel faillock (account lockout)
Default: yes
Priority: 950
Auth-Type: Primary
Auth:
    [default=die] pam_faillock.so preauth silent deny=5 unlock_time=900 fail_interval=900
    [success=1 default=bad] pam_unix.so nullok try_first_pass
    [default=die] pam_faillock.so authfail deny=5 unlock_time=900 fail_interval=900
Account-Type: Primary
Account:
    required pam_faillock.so
EOF

cat > /tmp/sentinel-auth/usr/share/pam-configs/sentinel-pwquality <<'EOF'
Name: Sentinel pwquality (password strength)
Default: yes
Priority: 940
Password-Type: Primary
Password:
    requisite pam_pwquality.so retry=3 minlen=14 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 difok=4 maxrepeat=3 gecoscheck=1
    [success=1 default=ignore] pam_unix.so obscure use_authtok try_first_pass yescrypt
EOF

cat > /tmp/sentinel-auth/usr/share/pam-configs/sentinel-umask <<'EOF'
Name: Sentinel umask (027)
Default: yes
Priority: 930
Session-Type: Additional
Session:
    optional pam_umask.so umask=027
EOF

cat > /tmp/sentinel-auth/etc/profile.d/00-sentinel-umask.sh <<'EOF'
umask 027
EOF

cat > /tmp/sentinel-auth/etc/sudoers.d/90-sentinel-logging <<'EOF'
Defaults        logfile="/var/log/sudo.log"
Defaults        loglinelen=0
Defaults        iolog_dir="/var/log/sudo-io"
Defaults        iolog_file="%{seq}"
Defaults        log_output
EOF
chmod 0440 /tmp/sentinel-auth/etc/sudoers.d/90-sentinel-logging

cat > /tmp/sentinel-auth/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -eu
install -d -m 0700 /var/log/sudo-io || true
touch /var/log/sudo.log || true
chmod 0600 /var/log/sudo.log || true
if command -v pam-auth-update >/dev/null 2>&1; then
  pam-auth-update --force >/dev/null 2>&1 || true
fi
EOF
chmod +x /tmp/sentinel-auth/DEBIAN/postinst

build_deb "sentinel-auth" "1.0.0" "/tmp/sentinel-auth"

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

mkdir -p config/includes.chroot/usr/share/backgrounds/sentinel
mkdir -p config/includes.chroot/usr/share/icons/sentinel
mkdir -p config/includes.chroot/usr/share/themes/sentinel

mkdir -p config/includes.chroot/etc/skel/.config/mate/desktop/background
mkdir -p config/includes.chroot/etc/skel/.config/mate/interface
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

# PAM deps (explicit; sentinel-auth also depends)
libpam-pwquality
libpam-modules
libpam-runtime

# Sentinel policy packages (local .deb)
sentinel-release
sentinel-hardening
sentinel-firewall
sentinel-auth
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
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev"
LIVE_USER_PASSWORD=""
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
  exit 0
fi
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
systemctl enable sentinel-live-guard.service >/dev/null 2>&1 || true
systemctl enable sentinel-nftables.service >/dev/null 2>&1 || true
systemctl enable apparmor.service >/dev/null 2>&1 || true
systemctl enable unattended-upgrades.service >/dev/null 2>&1 || true
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