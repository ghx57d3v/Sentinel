Sentinel OS – v1.0 ISO Build System

Sentinel OS is a hardened, security-focused Debian-based operating system designed for developers, blue team, red team, and purple team workflows, with an emphasis on stability, auditability, and correctness.

This repository contains the official v1.0 ISO build system, implemented using Debian live-build and targeting Debian 12 (Bookworm) with the MATE desktop environment.

PROJECT GOALS

Sentinel OS v1.0 prioritises:
- Deterministic, reproducible ISO builds
- Debian Stable (Bookworm) compatibility
- Minimal but solid security baseline
- Separation of base OS and advanced tooling
- Clean upgrade path for future versions

Sentinel OS v1.0 intentionally avoids:
- External repositories
- Vendor binaries
- Unstable or renamed Debian packages
- Runtime system mutation during ISO build

=====================================================================
BASE PLATFORM
=====================================================================

- Upstream: Debian GNU/Linux 12 (Bookworm)
- Architecture: amd64 only
- Desktop Environment: MATE
- Display Manager: LightDM
- Build Toolchain: live-build (20230502)

=====================================================================
INCLUDED FEATURES (v1.0)
=====================================================================

Desktop & UX:
- MATE Desktop
- LightDM (GTK greeter)
- NetworkManager

Security Baseline:
- AppArmor enabled
- Firejail with profiles
- UFW (default deny incoming)
- Kernel hardening via sysctl
- Avahi and Bluetooth disabled by default

Core Tooling (Bookworm-native):
- nmap
- wireshark
- lynis
- clamav
- yara
- sleuthkit
- gnupg / kleopatra
- cryptsetup
- tor / torsocks / nyx
- firefox-esr
- chromium
- developer utilities (git, geany, curl, jq, python3)
- office utilities (libre office, mousepad, pluma)

Advanced tooling such as OpenVAS, osquery, Zeek, VeraCrypt, Tor Browser,
automotive tooling, and exploit frameworks are intentionally deferred to
post-install profiles and/or later Sentinel OS releases.

=====================================================================
REPOSITORY CONTENTS
=====================================================================

- sentinel_iso_builder.sh
- README (this document)

The build script is a phased, interactive ISO builder that:
- Validates host architecture
- Installs build dependencies
- Configures live-build correctly for Bookworm
- Writes repositories and package lists
- Applies hardening safely at the binary stage
- Produces a bootable ISO image

=====================================================================
REQUIREMENTS
=====================================================================

Host System:
- Debian 12 (Bookworm) recommended
- amd64 CPU
- 30–50 GB free disk space
- Minimum 8 GB RAM (16 GB recommended)

User Requirements:
- Non-root user
- sudo access

=====================================================================
BUILD INSTRUCTIONS
=====================================================================

chmod +x sentinel_iso_builder.sh
./sentinel_iso_builder.sh

The script walks through PHASES 0–8 interactively.
Expected build time: 20–60 minutes.

The resulting ISO will be created in the working directory.

=====================================================================
DESIGN PHILOSOPHY
=====================================================================

Sentinel OS follows these principles:
- Correct before clever
- Stable before feature-rich
- Base OS first, tooling later
- Security by configuration, not hacks

=====================================================================
VERSIONING STRATEGY
=====================================================================

- v1.0: Stable base OS and security baseline
- v1.1+: Optional tooling profiles and research additions
- Future: Multiple editions (Core / Research / Developer)

=====================================================================
STATUS
=====================================================================

Sentinel OS v1.0 – Base ISO build system complete (pending ISO validation).

Next steps include:
- ISO boot testing
- Installer validation
- First-boot hardening service
- Post-install tooling profiles
