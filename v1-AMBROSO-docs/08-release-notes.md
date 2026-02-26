# Release Notes — SentinelOS v1.0 (Core)

Release: **2026-02-26**

## Base
- Debian GNU/Linux 13 (trixie), amd64
- live-build ISO-hybrid

## Desktop
- MATE Desktop Environment
- LightDM + lightdm-gtk-greeter
- Live user autologin: `sentinel`

## Security baseline
- AppArmor enabled
- Sysctl baseline applied
- Kernel boot hardening parameters via `bootappend-live`

## Platform features
- Optional ISO EFI signing hook (requires keys in `./secureboot`)
- TPM PCR measurement logging service (if TPM present)
