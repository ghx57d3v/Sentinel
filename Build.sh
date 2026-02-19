#!/usr/bin/env bash
set -euo pipefail

############################################
# SentinelOS v1.0
# Sentinel Standard Production Builder
############################################

DIST="bookworm"
ARCH="amd64"
LIVE_USER="sentinel"
VERSION="1.0-AMBROSO"
ISO_NAME="SentinelOS_${VERSION}_${ARCH}"
BUILD_DATE="$(date -u +%Y-%m-%d)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'nogit')"

echo "=============================================="
echo " SentinelOS Sentinel Standard Build"
echo "=============================================="
echo "Version    : ${VERSION}"
echo "Commit     : ${GIT_COMMIT}"
echo "Build Date : ${BUILD_DATE}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root."
    exit 1
fi

export SOURCE_DATE_EPOCH="$(git log -1 --pretty=%ct 2>/dev/null || date +%s)"
export LC_ALL=C
export TZ=UTC

############################################
# Clean
############################################

lb clean --purge || true

############################################
# Secure Boot Keys
############################################

mkdir -p secureboot

for key in PK KEK db; do
openssl req -new -x509 -newkey rsa:4096 -nodes \
  -keyout secureboot/${key}.key \
  -out secureboot/${key}.crt \
  -subj "/CN=SentinelOS ${key}/" -days 3650

openssl x509 -outform DER \
  -in secureboot/${key}.crt \
  -out secureboot/${key}.cer

sign-efi-sig-list -k secureboot/${key}.key \
  -c secureboot/${key}.crt \
  ${key} secureboot/${key}.cer \
  secureboot/${key}.auth || true
done

############################################
# Directory Structure
############################################

mkdir -p config/package-lists
mkdir -p config/includes.chroot/etc/{skel,lightdm,sysctl.d,systemd/system,xdg/gtk-3.0}
mkdir -p config/includes.chroot/usr/local/{sbin,bin}
mkdir -p config/includes.chroot/usr/share/{themes/Sentinel-Dark,grub/themes/sentinelos,plymouth/themes/sentinelos}
mkdir -p config/hooks/{normal,binary}

############################################
# Package List
############################################

cat > config/package-lists/sentinelos-core.list.chroot <<EOF
live-boot
live-config
mate-desktop-environment
lightdm
lightdm-gtk-greeter
firefox-esr
git
inkscape
kleopatra
veracrypt
mat2
exiftool
gimp
gnome-disk-utility
usbimager
gnupg
apparmor
apparmor-utils
sbsigntool
tpm2-tools
openssl
efitools
grub-efi-amd64-signed
shim-signed
plymouth
EOF

############################################
# Kernel Hardening Hook
############################################

cat > config/hooks/normal/0500-sentinel-hardening.hook.chroot <<'EOF'
#!/usr/bin/env bash
set -e

PARAMS="kernel.lockdown=integrity ima_policy=tcb ima_hash=sha256 lsm=lockdown,yama,apparmor apparmor=1 security=apparmor slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on pti=on"

if ! grep -q "kernel.lockdown=" /etc/default/grub; then
    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/&${PARAMS} /" /etc/default/grub
fi

systemctl enable apparmor || true
systemctl enable sentinelos-tpm-log.service || true

update-grub || true
update-initramfs -u
EOF

chmod +x config/hooks/normal/0500-sentinel-hardening.hook.chroot

############################################
# Sysctl Hardening
############################################

cat > config/includes.chroot/etc/sysctl.d/99-sentinel.conf <<EOF
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
kernel.unprivileged_userns_clone = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
EOF

############################################
# TPM Logging Service
############################################

cat > config/includes.chroot/etc/systemd/system/sentinelos-tpm-log.service <<'EOF'
[Unit]
Description=SentinelOS TPM Boot Measurement Log
ConditionPathExists=/dev/tpm0
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/usr/bin/tpm2_pcrread sha256:0,1,2,3,4,5,6,7 > /var/log/tpm-pcr.log 2>/dev/null'

[Install]
WantedBy=multi-user.target
EOF

############################################
# Kernel Resign Automation
############################################

cat > config/includes.chroot/usr/local/sbin/sentinelos-kernel-resign <<'EOF'
#!/usr/bin/env bash
KEY_DIR="/root/secureboot-keys"
CERT="${KEY_DIR}/db.crt"
KEY="${KEY_DIR}/db.key"

[ -f "$CERT" ] || exit 0
[ -f "$KEY" ] || exit 0

for kernel in /boot/vmlinuz-*; do
    sbverify --cert "$CERT" "$kernel" >/dev/null 2>&1 || \
    sbsign --key "$KEY" --cert "$CERT" --output "${kernel}.signed" "$kernel" && \
    mv "${kernel}.signed" "$kernel"
done
EOF

chmod +x config/includes.chroot/usr/local/sbin/sentinelos-kernel-resign

############################################
# GTK Theme
############################################

GTK_DIR="config/includes.chroot/usr/share/themes/Sentinel-Dark"
mkdir -p ${GTK_DIR}/gtk-3.0

cat > ${GTK_DIR}/gtk-3.0/gtk.css <<'EOF'
window {
    background-color: #0f1115;
    color: #e6e6e6;
}
button {
    background-color: #1a1d23;
    border-radius: 6px;
    border: 1px solid #00ffaa;
    color: #00ffaa;
}
button:hover {
    background-color: #00ffaa;
    color: #0f1115;
}
EOF

cat > ${GTK_DIR}/index.theme <<EOF
[Desktop Entry]
Name=Sentinel-Dark
Type=GTK
EOF

cat > config/includes.chroot/etc/xdg/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=Sentinel-Dark
gtk-application-prefer-dark-theme=1
EOF

############################################
# GRUB Theme
############################################

GRUB_DIR="config/includes.chroot/usr/share/grub/themes/sentinelos"

cat > ${GRUB_DIR}/theme.txt <<EOF
title-text: "SentinelOS"
title-font: "DejaVu Sans 32"
desktop-image: "background.png"
+ boot_menu {
    left = 25%
    width = 50%
    top = 40%
    height = 30%
    item_font = "DejaVu Sans 18"
    item_color = "#CCCCCC"
    selected_item_color = "#00ffaa"
}
EOF

touch ${GRUB_DIR}/background.png.txt
touch ${GRUB_DIR}/logo.png.txt

############################################
# Plymouth Animated Theme
############################################

PLY_DIR="config/includes.chroot/usr/share/plymouth/themes/sentinelos"

cat > ${PLY_DIR}/sentinelos.plymouth <<EOF
[Plymouth Theme]
Name=SentinelOS
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/sentinelos
ScriptFile=/usr/share/plymouth/themes/sentinelos/sentinelos.script
EOF

cat > ${PLY_DIR}/sentinelos.script <<'EOF'
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
logo = Image("logo.png");
sprite = Sprite(logo);
sprite.SetPosition(screen_width/2, screen_height/2, 0);
opacity = 0;
fun animate() {
  if (opacity < 1) { opacity += 0.02; sprite.SetOpacity(opacity); }
  Window.Refresh();
}
Plymouth.SetRefreshFunction(animate);
EOF

touch ${PLY_DIR}/background.png.txt
touch ${PLY_DIR}/logo.png.txt

############################################
# Configure live-build
############################################

lb config \
  --distribution "$DIST" \
  --architectures "$ARCH" \
  --archive-areas "main contrib non-free non-free-firmware" \
  --binary-images iso-hybrid \
  --bootappend-live "boot=live components splash username=${LIVE_USER}" \
  --debian-installer live \
  --iso-application "SentinelOS" \
  --iso-volume "SENTINELOS_${VERSION}"

############################################
# Build ISO
############################################

lb build
mv live-image-amd64.hybrid.iso "${ISO_NAME}.iso"

sha256sum "${ISO_NAME}.iso" > "${ISO_NAME}.sha256"

echo ""
echo "Sentinel Standard Build Complete"
echo "  ${ISO_NAME}.iso"
echo "  ${ISO_NAME}.sha256"
echo ""