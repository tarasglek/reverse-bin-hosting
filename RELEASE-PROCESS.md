# Release Process (reverse-bin-hosting)

This project ships a Debian package in addition to binary release artifacts.

## Dependency gate

`make deps-check` updates the Go toolchain, every runtime in `packaging/runtime-versions.env`, and every GitHub Action (pinact, SHA-pinned) to latest, and fails when that changed a file. Commit the diff, then:

```bash
make deps-check
make deb
```

## Vulnerability gate

After `make deb`, `make vulncheck` runs govulncheck on the packaged Go binaries. It fails when `reverse-bin-caddy`, which we build, links a vulnerable symbol that has a released fix. Prebuilt upstream binaries (detector, sops, age) are not scanned: the dependency gate holds them at their latest release, so a fix needs an upstream release. landrun is not scanned yet: its cached build can predate the current Go. CI runs it on every push and before publishing.

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
