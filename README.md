# Sentinel OS

Sentinel OS is a hardened, Debian-based operating system designed for
developers, blue team defenders, and red team operators who want a
secure-by-default base without sacrificing transparency or control.

## Design Goals

- Debian stable base (Bookworm)
- Bare-metal first
- Conservative, auditable hardening
- Modular security via policy packages
- Live environment for evaluation only
- No silent or opaque behavior

## Architecture

Sentinel OS is built using Debian live-build and layers security through
explicit, versioned policy packages:

- `sentinel-release` – OS identity and APT policy
- `sentinel-hardening` – kernel, sysctl, journald, updates
- `sentinel-firewall` – nftables baseline firewall
- `sentinel-auth` – PAM and sudo hardening

This approach allows:
- Easy auditing
- Selective enablement
- Future profiles (server, workstation, red team, blue team)

## Live vs Installed System

**Live Session**
- Non-admin user
- No password
- Optional autologin
- Warning banner
- No assumption of trust

**Installed System**
- Full hardening enabled
- Firewall active
- AppArmor enforcing
- Automatic security updates

## Build Script

The ISO build script:
- Builds all Sentinel policy packages locally
- Injects them into the live-build environment
- Supports interactive and CI mode (`--ci`)
- Produces a reproducible ISO with checksums

## Intended Audience

- Security engineers
- Developers
- Incident responders
- Red team / blue team practitioners
- Anyone who wants a clean, hardened Debian base

## Non-Goals

- No distro lock-in
- No hidden telemetry
- No aggressive hardening that breaks workflows
- No VM-optimized defaults

## Status

- v1.0.0: Foundation release
- Secure Boot planned for later versions
