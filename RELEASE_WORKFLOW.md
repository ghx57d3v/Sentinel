Sentinel OS – Build & Release Workflow (v1)
==================================================

1. Purpose
-----------
This workflow defines how Sentinel OS progresses from source and policy packages to a bootable, installable, and releasable ISO.

It establishes clear boundaries between:
build mechanics
validation
human acceptance
release artifacts
The goal is repeatability, trust, and minimal surprise.

2. Roles & Responsibilities
----------------------------
Build Script (build-iso.sh)
Responsible for:
assembling Sentinel policy packages
configuring live-build
producing a deterministic ISO artifact
generating checksums
Not responsible for:
deciding release readiness
testing behavior
publishing artifacts
Validation Scripts (tools/)
Responsible for:
proving the ISO behaves as designed
enforcing security baselines
blocking bad releases
Release Manager (human or CI)
Responsible for:
versioning
changelogs
final sign-off
publishing

3. Workflow Phases
-------------------
* PHASE A — Pre-Build Preparation *
Owner: Human / CI
Frequency: Once per release
Checklist:
Increment version numbers:
ISO version
Sentinel policy package versions
Review policy changes:
sentinel-hardening
sentinel-auth
sentinel-firewall
optional packages
Update CHANGELOG.md
Ensure repository is clean and tagged
Exit condition: Release intent declared.

* PHASE B — Build *
Owner: build-iso.sh
Frequency: Every release / CI run
Steps:
Host sanity checks
Dependency installation
Clean build workspace
Build Sentinel policy packages
Configure live-build
Inject policy packages and configs
Build ISO
Generate SHA256 checksum
Artifacts produced:
Sentinel-OS-vX.Y.Z-bookworm-amd64.iso
Sentinel-OS-vX.Y.Z-bookworm-amd64.iso.sha256
build.log
Exit condition: ISO successfully built.

* PHASE C — Automated Validation *
Owner: Validation scripts
Frequency: Every build
C1: Live Validation
Boot ISO in VM or test hardware:
Live session boots to MATE
“LIVE – NOT SECURE” warning visible
Live user:
no sudo
password locked
Network functional (DHCP)
No crashes or login loops
C2: Installed Validation
Install Sentinel OS and reboot:
No autologin
Firewall active (nft list ruleset)
AppArmor enforcing (aa-status)
PAM policy active (faillog, pam-auth-update)
Unattended upgrades enabled
No unexpected listening ports (ss -lntup)
Exit condition: All checks pass.

* PHASE D — Human Acceptance *
Owner: Maintainer
Frequency: Every release candidate
Tests on real hardware:
UEFI + BIOS boot
Wi-Fi / Ethernet
Suspend / resume
Installer UX
Exit condition: Manual approval.

* PHASE E — Release Assembly *
Owner: Release manager
Steps:
Create release directory:
releases/X.Y.Z/
  ├── Sentinel-OS-vX.Y.Z-bookworm-amd64.iso
  ├── Sentinel-OS-vX.Y.Z-bookworm-amd64.iso.sha256
  ├── build-info.txt
  ├── CHANGELOG.md
Sign artifacts (optional but recommended):
minisign or GPG
Tag git repository
Exit condition: Release artifacts finalized.

* PHASE F — Distribution *
Owner: Project
Publish ISO
Publish checksums + signatures
Publish install notes
Announce release

4. Non-Goals (Explicit)
-----------------------
This workflow intentionally excludes:
Secure Boot (future)
Continuous deployment
Toolchain upgrades mid-release
Feature development during release phase

5. Principles
--------------
Policy lives in packages, not scripts
Builds are deterministic
Validation blocks releases
Defaults are safe
Opt-in remains opt-in