#!/usr/bin/env bash
set -e

########################################
# SentinelOS Core Build Script
# Debian 12 Bookworm
########################################

VERSION="1.0"
EDITION="AMBROSO"
ARCH="amd64"
DIST="bookworm"

ISO_NAME="SentinelOS-${VERSION}-${EDITION}-${ARCH}.iso"

echo "[*] Cleaning previous build..."
lb clean || true
rm -rf config

echo "[*] Configuring live-build..."

lb config \
  --distribution ${DIST} \
  --architectures ${ARCH} \
  --binary-images iso-hybrid \
  --debian-installer live \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components quiet splash"

########################################
# PACKAGE LIST
########################################

mkdir -p config/package-lists

cat <<EOF > config/package-lists/sentinelos-core.list.chroot
mate-desktop-environment-core
lightdm
lightdm-gtk-greeter
gnome-disk-utility
gimp
inkscape
geany
firefox-esr
libreoffice
git
gnupg
kleopatra
veracrypt
pidgin
nftables
apparmor
apparmor-utils
auditd
aide
unattended-upgrades
fail2ban
plymouth
grub-pc
mat2
exiftool
tpm2-tools
tpm2-abrmd
clevis
EOF

cat <<EOF > config/includes.chroot/usr/share/themes/Sentinel-Dark/gtk-3.0/settings.ini
[Settings]
gtk-application-prefer-dark-theme=1
EOF

########################################
# BRANDING STRUCTURE
########################################

mkdir -p config/includes.chroot/etc/lightdm
mkdir -p config/includes.chroot/etc/dconf/db/local.d
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/usr/share/backgrounds/sentinelos
mkdir -p config/includes.chroot/usr/share/grub/themes/sentinelos
mkdir -p config/includes.chroot/usr/share/plymouth/themes/sentinelos
mkdir -p config/includes.chroot/etc/sysctl.d
mkdir -p config/hooks/normal

########################################
# OS RELEASE
########################################

cat <<EOF > config/includes.chroot/etc/os-release
NAME="SentinelOS"
VERSION="${VERSION} AMBROSO"
ID=sentinelos
ID_LIKE=debian
PRETTY_NAME="SentinelOS ${VERSION} Core"
VERSION_ID="${VERSION}"
HOME_URL="https://sentinel.local"
SUPPORT_URL="https://sentinel.local/support"
BUG_REPORT_URL="https://sentinel.local/issues"
EOF

########################################
# LIGHTDM CONFIG
########################################

cat <<EOF > config/includes.chroot/etc/lightdm/lightdm.conf
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

cat <<EOF > config/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
background=/usr/share/backgrounds/sentinelos/default.jpg
theme-name=Adwaita-dark
icon-theme-name=Adwaita
font-name=Sans 11
EOF

########################################
# TERMINAL PROMPT
########################################

cat <<'EOF' >> config/includes.chroot/etc/skel/.bashrc

# SentinelOS Gold Prompt
PS1='\[\e[38;5;220m\]\u\[\e[0m\]@\h:\w\$ '
EOF

########################################
# DCONF (MATE)
########################################

cat <<EOF > config/includes.chroot/etc/dconf/db/local.d/01-sentinelos
[org/mate/desktop/background]
picture-filename='/usr/share/backgrounds/sentinelos/default.jpg'
picture-options='zoom'

[org/mate/interface]
gtk-theme='Sentinel-Dark'
icon-theme='Adwaita'
EOF

########################################
# SECURITY BASELINE
########################################

cat <<EOF > config/includes.chroot/etc/sysctl.d/99-sentinelos.conf
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.all.accept_redirects=0
EOF

########################################
# GRUB THEME
########################################

cat <<EOF > config/includes.chroot/usr/share/grub/themes/sentinelos/theme.txt
+ desktop-image {
    file = "background.png"
}

+ image {
    top = 18%
    left = 50%
    width = 220
    height = 220
    file = "logo.png"
}

+ label {
    top = 10%
    left = 0
    width = 100%
    align = "center"
    text = "SentinelOS ${VERSION} AMBROSO"
    font = "DejaVu Sans Bold 28"
    color = "#F2C200"
}

+ boot_menu {
    left = 30%
    top = 50%
    width = 40%
    height = 30%
    item_font = "DejaVu Sans Regular 18"
    item_color = "#CCCCCC"
    selected_item_color = "#000000"
    selected_item_pixmap_style = "select_box"
    item_height = 38
    item_padding = 10
    item_spacing = 8
}

+ pixmap_style select_box {
    background_color = "#F2C200"
    border_color = "#D6AD00"
    border_width = 2
}

+ label {
    bottom = 2%
    left = 0
    width = 100%
    align = "center"
    text = "Secure Boot Verified"
    font = "DejaVu Sans Regular 14"
    color = "#888888"
}
EOF

########################################
# PLYMOUTH THEME
########################################

cat <<EOF > config/includes.chroot/usr/share/plymouth/themes/sentinelos/sentinelos.plymouth
[Plymouth Theme]
Name=SentinelOS
Description=SentinelOS Secure Boot Splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/sentinelos
ScriptFile=/usr/share/plymouth/themes/sentinelos/sentinelos.script
EOF

cat <<'EOF' > config/includes.chroot/usr/share/plymouth/themes/sentinelos/sentinelos.script
Window.SetBackgroundTopColor (0.06, 0.06, 0.06);
Window.SetBackgroundBottomColor (0.12, 0.12, 0.12);

logo = Image("logo.png");
logo_sprite = Sprite(logo);

logo_sprite.SetX(Window.GetWidth()/2 - logo.GetWidth()/2);
logo_sprite.SetY(Window.GetHeight()/2 - logo.GetHeight()/2 - 60);
logo_sprite.SetOpacity(0.0);

progress_width  = 400;
progress_height = 4;

progress_x = Window.GetWidth()/2 - progress_width/2;
progress_y = Window.GetHeight()/2 + 120;

progress_bg = Rectangle(progress_width, progress_height);
progress_bg.SetPosition(progress_x, progress_y);
progress_bg.SetColor(0.25, 0.25, 0.25);

progress_fill = Rectangle(progress_width, progress_height);
progress_fill.SetPosition(progress_x, progress_y);
progress_fill.SetColor(0.95, 0.76, 0.0);
progress_fill.SetWidth(0);

bg_sprite = Sprite(progress_bg);
fill_sprite = Sprite(progress_fill);
fill_sprite.SetOpacity(0.0);

fade_step = 0.02;
current_opacity = 0.0;

function animate_callback () {
    if (current_opacity < 1.0) {
        current_opacity += fade_step;
        logo_sprite.SetOpacity(current_opacity);
        fill_sprite.SetOpacity(current_opacity);
    }
}

function update_callback (progress_value) {
    progress_fill.SetWidth(progress_width * progress_value);
}

Plymouth.SetRefreshFunction(animate_callback);
Plymouth.SetUpdateFunction(update_callback);
EOF


########################################
# CUSTOM GTK THEME
########################################

mkdir -p config/includes.chroot/usr/share/themes/Sentinel-Dark/gtk-3.0

cat <<'EOF' > config/includes.chroot/usr/share/themes/Sentinel-Dark/gtk-3.0/gtk.css
@define-color sentinel_bg #2E2E2E;
@define-color sentinel_panel #3A3A3A;
@define-color sentinel_gold #F2C200;
@define-color sentinel_gold_dark #D6AD00;
@define-color sentinel_text #EAEAEA;

window {
    background-color: @sentinel_bg;
    color: @sentinel_text;
}

button {
    background-color: @sentinel_panel;
    border-radius: 4px;
    border: 1px solid #444;
}

button:hover {
    background-color: @sentinel_gold_dark;
    color: #000000;
}

button:checked,
button:active {
    background-color: @sentinel_gold;
    color: #000000;
}

selection {
    background-color: @sentinel_gold;
    color: #000000;
}

entry {
    background-color: #1E1E1E;
    border: 1px solid #444;
}

headerbar {
    background-color: @sentinel_panel;
    border-bottom: 1px solid #444;
}
EOF

########################################
# BRANDING HOOK (SECURE BOOT SAFE)
########################################

# Inject secure kernel parameters
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&kernel.lockdown=integrity ima_policy=tcb ima_hash=sha256 /' /etc/default/grub

# TPM Logging Service
cat <<SERVICE > /etc/systemd/system/sentinelos-tpm-log.service
[Unit]
Description=SentinelOS TPM Boot Measurement Log
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/usr/bin/tpm2_pcrread sha256:0,1,2,3,4,5,6,7 > /var/log/tpm-pcr.log'

[Install]
WantedBy=multi-user.target
SERVICE

systemctl enable sentinelos-tpm-log.service

update-grub || true

chmod +x config/hooks/normal/010-branding.hook.chroot

########################################
# BUILD METADATA
########################################

mkdir -p config/includes.chroot/etc/sentinelos

cat <<EOF > config/includes.chroot/etc/sentinelos/build-info
SentinelOS ${VERSION} AMBROSO
Architecture: ${ARCH}
Build-Date: $(date -u)
Secure-Boot: Supported
Kernel-Lockdown: integrity
EOF

########################################
# BUILD ISO
########################################

echo "[*] Building ISO..."
lb build

mv live-image-${ARCH}.hybrid.iso ${ISO_NAME}

echo "[+] Build complete: ${ISO_NAME}"

echo "[*] Generating checksums..."
sha256sum ${ISO_NAME} > ${ISO_NAME}.sha256

echo "[*] Signing ISO..."
gpg --detach-sign --armor ${ISO_NAME}
gpg --detach-sign ${ISO_NAME}
