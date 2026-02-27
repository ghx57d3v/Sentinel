# Test Plan & Debug Playbook (v1)

## Smoke tests
```bash
cat /proc/cmdline
cat /sys/kernel/security/lockdown
sudo aa-status
sysctl kernel.kptr_restrict kernel.dmesg_restrict 2>/dev/null || true
```

## Desktop tests (when GUI works)
```bash
gsettings get org.mate.desktop.interface gtk-theme
gsettings get org.mate.desktop.background picture-filename
```

## GUI failure triage
```bash
systemctl status lightdm --no-pager
ls -la /var/log/lightdm || true
sudo tail -n 200 /var/log/lightdm/lightdm.log 2>/dev/null || true
sudo tail -n 200 /var/log/lightdm/x-0.log 2>/dev/null || true
```

## VM guidance
- SPICE + QXL recommended
- Disable 3D acceleration if unstable
