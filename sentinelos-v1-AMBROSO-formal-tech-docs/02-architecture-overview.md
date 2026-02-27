# Architecture Overview

## 1. High-level components
- **Build Host**: Debian-based machine running `live-build`
- **Build Pipeline**: `Build.sh` orchestrates clean, configure, build, and artifact naming/hashing
- **Live Image**:
  - Linux kernel + initrd provided by Debian packages
  - `live-boot`/`live-config` for live environment initialization
  - MATE desktop stack
  - LightDM display manager with autologin for user `sentinel`

## 2. Overlay model
SentinelOS customizations are delivered through:
- `config/includes.chroot/**` (file overlays copied into the final rootfs)
- `config/hooks/normal/*.hook.chroot` (actions executed inside chroot during build)
- `config/hooks/binary/*.hook.binary` (actions executed on ISO assembly stage)

## 3. Control planes
- **Boot policy plane**: kernel parameters via `--bootappend-live`
- **Runtime policy plane**:
  - sysctl baseline `/etc/sysctl.d/99-sentinelos.conf`
  - AppArmor enablement + profiles (packaged + optional custom)
  - TPM PCR logging service

## 4. Known platform dependencies
VM testing relies on virt-manager configuration for stable display output:
- SPICE display
- QXL video
- 3D/OpenGL disabled (if unstable)
