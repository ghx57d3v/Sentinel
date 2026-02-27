# Security Baseline Specification (v1)

## 1. Boot hardening parameters
Applied via `--bootappend-live` and must appear in `/proc/cmdline`.

Minimum baseline:
- `kernel.lockdown=integrity`
- `ima_policy=tcb`
- `ima_hash=sha256`
- `lsm=lockdown,yama,apparmor`
- `apparmor=1`
- `security=apparmor`
- `slab_nomerge`
- `init_on_alloc=1`
- `init_on_free=1`
- `page_alloc.shuffle=1`
- `randomize_kstack_offset=on`
- `pti=on`

## 2. AppArmor
Validation:
```bash
sudo aa-status
```

## 3. Sysctl baseline
Validation:
```bash
sysctl kernel.kptr_restrict kernel.dmesg_restrict kernel.unprivileged_bpf_disabled
```
