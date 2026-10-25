# Release Process (reverse-bin-hosting)

This project ships a Debian package in addition to binary release artifacts.

## Dependency gate

`make deps-check` updates the Go toolchain, every runtime in `packaging/runtime-versions.env`, and every GitHub Action (pinact, SHA-pinned) to latest, and fails when that changed a file. Commit the diff, then:

```bash
make deps-check
make deb
```

## Release notes

Add `release-notes/vX.Y.Z.md` before tagging: at most 100 words, dense and terse. `make release-notes TAG=vX.Y.Z` checks it; tagged CI reruns the check and publishes the file as the release body.

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
