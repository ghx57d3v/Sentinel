# Filesystem & Overlay Specification

## 1. Overlay mapping
Everything under `config/includes.chroot/` is copied into the live root filesystem preserving path.

## 2. Critical overlay files
- `/etc/dconf/profile/user`
- `/etc/dconf/db/local.d/*`
- `/etc/lightdm/lightdm.conf`
- `/etc/lightdm/lightdm-gtk-greeter.conf`
- `/etc/lightdm/lightdm.conf.d/50-sentinelos-live.conf`
- `/etc/sysctl.d/99-sentinelos.conf`
- `/etc/systemd/system/sentinelos-tpm-log.service`

## 3. Hook responsibilities
- Ensure LightDM runtime dirs exist (e.g., `/var/lib/lightdm/data`) to avoid greeter failure
- Compile dconf database (`dconf update`)
- Compile GSettings schemas (`glib-compile-schemas /usr/share/glib-2.0/schemas`)
- Apply plymouth default, update initramfs
