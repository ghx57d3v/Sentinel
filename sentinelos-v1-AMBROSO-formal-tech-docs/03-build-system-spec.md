# Build System Specification

## 1. Inputs
- `Build.sh`: orchestrates the build; may generate parts of `config/`
- `config/package-lists/sentinelos-core.list.chroot`: package selection (source of truth)
- `config/includes.chroot/**`: overlay files included in the chroot filesystem
- `config/hooks/**`: build hooks

## 2. Build Steps (canonical)
1. Purge prior state:
   - `lb clean --purge`
   - remove `.build chroot binary cache`
2. Configure:
   - `lb config --distribution trixie --architectures amd64 ...`
3. Build:
   - `lb build`
4. Artifact naming:
   - rename output ISO to `SentinelOS_1.0-AMBROSO_amd64.iso`
   - write hash file `SentinelOS_1.0-AMBROSO_amd64.sha256`

## 3. Configuration invariants
- Distribution: `trixie`
- Archive areas: `main contrib non-free non-free-firmware`
- Image: `iso-hybrid`
- Installer: `debian-installer live`
- Live user: `username=sentinel` passed via `--bootappend-live`

## 4. Boot parameters (source of truth)
Kernel parameters MUST be set via `--bootappend-live` (not by editing `/etc/default/grub` inside chroot).

## 5. Idempotency rules
- Hooks must not require `sudo` (executed as root in chroot).
- Hooks must be executable.
- Avoid `systemctl enable` in chroot; prefer symlink enablement where needed.
