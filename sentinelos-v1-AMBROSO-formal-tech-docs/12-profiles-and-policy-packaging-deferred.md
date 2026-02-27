# Profiles & Policy Packaging System (Deferred / Out of Scope for v1)

**Status:** Design placeholder only (not implemented in v1 build).  
**Purpose:** Document the intended direction so v1 remains orderly and forward-compatible without claiming functionality that does not yet exist.

## 1. Motivation
SentinelOS began as a single hardened workstation baseline. As the project evolved, the goal expanded to support *role-appropriate security posture and toolsets* without forking the OS or maintaining divergent images.

A “profiles” system would allow SentinelOS to ship:
- a minimal **Core** baseline
- optional role-based layers (e.g., **Workstation**, **Research**)
- policy bundles that can be audited and versioned

## 2. Non-goals for v1
v1 does **not** include:
- a profile selector UI at boot or install time
- a packaging mechanism that switches policy layers dynamically
- a formally versioned “policy ABI” guarantee

v1 provides only a **single baseline**: *SentinelOS Core*.

## 3. Intended design (future)
### 3.1 Profile model
Profiles are envisioned as additive layers on top of Core:

- **Core (baseline)**  
  - minimal apps + desktop + security baseline
  - consistent default posture and branding

- **Workstation (future)**  
  - expanded productivity/dev tools
  - additional safe defaults (browser hardening layer, etc.)

- **Research (future)**  
  - optional tooling that may reduce baseline safety assumptions
  - explicitly separated to keep Core conservative

### 3.2 Policy packaging approach (future)
Preferred approach on Debian base:
- keep Core as a standard live-build image
- express profiles as *Debian packages* (meta-packages + config packages) or as *profile bundles* applied at build-time
- version policy bundles (e.g., `sentinel-policy-core`, `sentinel-policy-workstation`)
- ensure a clear precedence order:
  1. kernel cmdline baseline (bootappend-live)
  2. sysctl baseline
  3. LSM policies (AppArmor)
  4. application policies (browser, sandboxing rules)
  5. desktop defaults (dconf)

### 3.3 Implementation candidates
- **Meta-packages**: `sentinel-profile-core`, `sentinel-profile-workstation`  
  Dependencies pull in packages; postinst drops config into `/etc/sentinelos/…`.
- **Config packages**: `sentinel-policy-apparmor`, `sentinel-policy-sysctl`, etc.
- **Build-time selection**: Build.sh toggles which lists/packages are included.

## 4. Documentation rule
Until a profile mechanism is implemented and testable, all profile documentation remains:
- marked as **Deferred / Design**
- non-normative (does not define required behavior of v1)

_Last updated: 2026-02-27_
