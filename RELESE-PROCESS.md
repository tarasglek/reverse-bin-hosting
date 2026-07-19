# Release Process (caddy-reverse-bin)

This project ships a Debian package in addition to binary release artifacts.

## Runtime version gate

Before tagging a release, refresh bundled runtime versions and fail if the lockfile would change:

```bash
make update-runtime-versions
git diff --exit-code packaging/runtime-versions.env
make deb
```

If `packaging/runtime-versions.env` changed, review and commit that runtime bump first, then rerun the gate.

## Release notes gate

Before tagging `vX.Y.Z`, add `release-notes/vX.Y.Z.md`. Follow the categorized ESPHome/Home Assistant style used by existing notes:

- `# Reverse Bin vX.Y.Z`
- `## Highlights` with at least one user-facing bullet
- `## Breaking changes`, explicitly saying `None.` when applicable
- `## Full list of changes` with at least one bullet

Tagged CI validates this structure before publishing and uses the authored file as the GitHub release body. A missing or incomplete file fails the release instead of publishing empty or generic generated notes.

## Debian package validation

After `make deb`:

```bash
dpkg-deb -c ../reverse-bin_*_*.deb
```

Verify the package contains:

- `/usr/bin/reverse-bin-caddy`
- `/etc/reverse-bin/Caddyfile`
- `/usr/lib/reverse-bin/`
- the systemd unit
- `/usr/share/doc/reverse-bin/examples/`
- `/usr/share/reverse-bin/skills/reverse-bin-web-apps/SKILL.md`
