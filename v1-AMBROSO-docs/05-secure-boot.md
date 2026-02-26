# Secure Boot (Build-time) — v1

## Current scope
v1 supports **optional signing of EFI binaries inside the ISO** (if keys are provided).
This helps with custom ownership workflows, but it is not the whole story by itself.

## Keys
The build-time signing hook expects:
- `./secureboot/db.crt`
- `./secureboot/db.key`

If absent, signing is skipped.

## What gets signed
The hook searches `binary/` for `*.efi` and signs each with `sbsign`.

## Testing Secure Boot
To test Secure Boot you generally need:
- OVMF (UEFI firmware) + Secure Boot enabled, and
- a trust chain that matches your signing approach.
