# Product Specification — SentinelOS v1.0 Core

## 1. Purpose
SentinelOS Core is a Debian-based live-installable workstation environment with an opinionated **security baseline**, **deterministic defaults**, and **Sentinel branding** out-of-the-box.

## 2. Scope (v1.0 Core)
### In-scope
- Debian 13 (trixie) amd64 live ISO built with `live-build`
- MATE desktop with LightDM and live-user autologin (`sentinel`)
- System defaults: theme, wallpaper, panel layout, terminal profile
- Baseline hardening: boot parameters, sysctl baseline, AppArmor enabled
- TPM PCR measurement logging to local log (if TPM present)
- Optional EFI signing of ISO contents (if keys provided)

### Out-of-scope (explicitly deferred)
- “Profile switching” / policy-packaging framework beyond baseline
- Remote attestation pipeline / measured boot verification service
- Production PK/KEK/db key lifecycle and device enrollment UX
- Installer customization beyond standard Debian live installer defaults

## 3. Target Users
- Single-user workstation operator requiring a consistent, hardened base OS.
- Primary objective: “fresh install is immediately usable and trusted”.

## 4. Non-Functional Requirements
- Reproducible: build is scripted and does not depend on ad-hoc edits inside chroot
- Deterministic defaults: system boots into consistent desktop state
- Maintainable: changes are made only in `Build.sh` and `config/*`
