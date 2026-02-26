# Project Layout (v1)

This repo is a standard `live-build` project plus SentinelOS overlays.

## Key directories
- `auto/`
  - `auto/config` (optional helper; live-build can call it internally)
  - `auto/build` (optional helper)
- `config/`
  - `package-lists/` — package selection
  - `includes.chroot/` — files copied into the live filesystem (chroot)
  - `hooks/normal/` — chroot hooks (run inside chroot during build)
  - `hooks/binary/` — binary hooks (run while assembling ISO contents)
  - `bootloaders/`, `binary/`, `chroot/`, `bootstrap/`, `source/` — live-build config outputs

## SentinelOS v1 overlays (current intent)
- `config/includes.chroot/etc/dconf/…` — system dconf defaults for MATE
- `config/includes.chroot/etc/lightdm/…` — LightDM + greeter config, live autologin
- `config/includes.chroot/etc/sysctl.d/…` — sysctl hardening
- `config/includes.chroot/etc/systemd/system/…` — `sentinelos-tpm-log.service`
- `config/includes.chroot/usr/share/themes/…` — `Sentinel-Dark` theme
- `config/includes.chroot/usr/share/plymouth/themes/…` — Plymouth theme
- `config/includes.chroot/usr/share/grub/themes/…` — GRUB theme
- `config/hooks/normal/0500-branding.hook.chroot` — compiles dconf/schemas, enables services, sets Plymouth, GRUB drop-in
- `config/hooks/binary/999-secureboot.hook.binary` — optional ISO EFI signing (if keys exist)

## Where files “live” in the final ISO
- Anything under `config/includes.chroot/` ends up inside the live root filesystem at the same path.
  - Example: `config/includes.chroot/etc/lightdm/lightdm.conf` → `/etc/lightdm/lightdm.conf` in the live OS.
