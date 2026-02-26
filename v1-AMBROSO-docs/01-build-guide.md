# Build Guide (v1)

## Host requirements
- Debian-based host (recommended: Debian 13 / trixie)
- `live-build` installed
- Root privileges to build (`sudo ./build.sh`)

## One-command build
From the project root:
```bash
sudo ./build.sh
```

The script:
- purges previous live-build state (`lb clean --purge`)
- removes build residue (`.build chroot binary cache`)
- runs `lb config` for Debian **trixie** amd64
- writes/updates `config/…` content (package lists, includes, hooks)
- runs `lb build`
- renames ISO to `SentinelOS_1.0-AMBROSO_amd64.iso`
- writes `SentinelOS_1.0-AMBROSO_amd64.sha256`

## Clean rebuild
A rebuild is simply running:
```bash
sudo ./build.sh
```

## Notes
- If you edit files inside `config/…`, be aware the build script may recreate/overwrite some of them depending on how it’s written.
- Prefer editing the canonical sources (the build script + files in `config/includes.*` and `config/hooks/*`) and keep them under version control.
