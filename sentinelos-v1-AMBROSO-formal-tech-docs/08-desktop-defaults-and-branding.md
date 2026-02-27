# Desktop Defaults & Branding (v1)

## 1. Defaults mechanism
- `/etc/dconf/profile/user`:
  - `user-db:user`
  - `system-db:local`
- Defaults in `/etc/dconf/db/local.d/*`
- Compiled by hook: `dconf update`

## 2. Schema compilation
- Hook compiles schemas:
  - `glib-compile-schemas /usr/share/glib-2.0/schemas`
- Ensure `gschemas.compiled` exists.

## 3. LightDM
- Autologin user: `sentinel`
- Ensure `/var/lib/lightdm/data` exists at runtime.
