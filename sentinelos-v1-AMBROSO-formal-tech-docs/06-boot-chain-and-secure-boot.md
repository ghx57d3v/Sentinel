# Boot Chain & Secure Boot (v1)

## 1. Live boot chain (conceptual)
Firmware → Bootloader → Kernel+initrd → live-boot → userspace → LightDM → MATE

## 2. Build-time EFI signing (optional)
Hook: `config/hooks/binary/999-secureboot.hook.binary`

Inputs:
- `secureboot/db.crt`
- `secureboot/db.key`

Behavior:
- If keys exist, sign all `*.efi` under the assembled `binary/` tree using `sbsign`.

## 3. Limitations
- EFI signing alone does not establish trust unless keys are enrolled or shim/MOK is used.
