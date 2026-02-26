# Testing & Debugging (v1)

## VM recommended settings (virt-manager / QEMU)
Commonly stable settings:
- Display: SPICE
- Video: QXL (or Virtio)
- Disable 3D acceleration if it causes issues

## Boot troubleshooting
Try:
- `systemd.unit=multi-user.target` (boot to TTY)
- `nomodeset` (diagnostics)
- `noplymouth nosplash` (see more boot output)

## Identify why GUI didn’t start
From TTY:
```bash
systemctl status lightdm --no-pager
systemctl status graphical.target --no-pager
ls -la /var/log/lightdm || true
```

## “All runlevel operations denied by policy”
During build, Debian’s `policy-rc.d` typically prevents services from starting in chroot.
That is normal for live-build; enablement is handled via symlinks/presets.
