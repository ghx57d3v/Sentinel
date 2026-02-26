# Branding & Theming (v1)

## MATE defaults via dconf
System defaults are set using:
- `/etc/dconf/profile/user` pointing to `system-db:local`
- `/etc/dconf/db/local.d/*.ini` (keyfiles) for defaults

The hook compiles them:
- `dconf update`

### Verify in live system
Once MATE is running:
```bash
gsettings get org.mate.desktop.interface gtk-theme
gsettings get org.mate.desktop.background picture-filename
```

If you see “No such schema…”, it typically means:
- schemas were not compiled, or
- gsettings/dconf packages are missing, or
- MATE session not actually running.

## LightDM
- Config lives under `/etc/lightdm/`
- Live autologin in `lightdm.conf.d/50-sentinelos-live.conf`

## Terminal branding
- `.bashrc` in `/etc/skel/.bashrc`
