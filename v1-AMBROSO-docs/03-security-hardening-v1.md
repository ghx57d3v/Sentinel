# Security & Hardening (v1)

This is the **v1 baseline**: practical hardening without “profiles” yet.

## Kernel boot parameters (live)
The build uses hardening-focused boot parameters via `--bootappend-live`, including:
- `kernel.lockdown=integrity`
- `ima_policy=tcb` + `ima_hash=sha256` (requires kernel support/config)
- `lsm=lockdown,yama,apparmor` + `apparmor=1` + `security=apparmor`
- `slab_nomerge`
- `init_on_alloc=1` + `init_on_free=1`
- `page_alloc.shuffle=1`
- `randomize_kstack_offset=on`
- `pti=on`

Verify in live system:
```bash
cat /proc/cmdline
cat /sys/kernel/security/lockdown
```

## AppArmor
Verify:
```bash
sudo aa-status
```

## Sysctl baseline
Verify:
```bash
sysctl kernel.kptr_restrict kernel.dmesg_restrict 2>/dev/null
sysctl kernel.unprivileged_bpf_disabled 2>/dev/null || true
```

## What v1 does NOT claim yet
- Full “profiles” switching system
- Verified secure boot chain on every target machine (depends on your key enrollment strategy)
- Strict measured boot attestation pipeline (v1 only logs PCRs locally if TPM present)
