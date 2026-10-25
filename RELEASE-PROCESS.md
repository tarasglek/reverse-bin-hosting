# Release Process (reverse-bin-hosting)

This project ships a Debian package in addition to binary release artifacts.

## Dependency gate

`make deps-check` updates the Go toolchain, every runtime in `packaging/runtime-versions.env`, and every GitHub Action (pinact, SHA-pinned) to latest, and fails when that changed a file. Commit the diff, then:

```bash
make deps-check
make deb
```

## Vulnerability gate

After `make deb`, `make vulncheck` runs govulncheck on the packaged Go binaries. It fails when `reverse-bin-caddy`, which we build, links a vulnerable symbol that has a released fix. Prebuilt upstream binaries (detector, landrun, sops, age) are not scanned: the dependency gate holds them at their latest release, so a fix needs an upstream release. CI runs it on every push and before publishing.

## Apt repository

Tagged CI attaches the `.deb` to a GitHub release, signs it into a flat apt repository (`make apt-repo` builds `site/`), and deploys that to GitHub Pages at `https://reverse-bin-hosting.coolness.fyi/`. Each deploy replaces the site, so hosts upgrade to the last deployed release. The site's custom domain is a DNS-only Cloudflare CNAME, reverse-bin-hosting.coolness.fyi → tarasglek.github.io. The repository needs the APT_SOPS_AGE_KEY secret and Pages publishing from Actions with that custom domain, with `v*` tags allowed to deploy:

```bash
gh secret set APT_SOPS_AGE_KEY < ci-age.key
gh api -X POST repos/tarasglek/reverse-bin-hosting/pages -f build_type=workflow
gh api -X PUT repos/tarasglek/reverse-bin-hosting/pages -f cname=reverse-bin-hosting.coolness.fyi
# once GitHub has issued the certificate:
gh api -X PUT repos/tarasglek/reverse-bin-hosting/pages -F https_enforced=true
gh api -X POST repos/tarasglek/reverse-bin-hosting/environments/github-pages/deployment-branch-policies -f name='v*' -f type=tag
```

The signing key is `packaging/apt/signing-key.sops.json`, encrypted with sops to every SSH key on the maintainers' GitHub accounts plus a CI age key whose private half is the `APT_SOPS_AGE_KEY` Actions secret. After adding or removing an SSH key on GitHub, run `make sync-sops-recipients` and commit `.sops.yaml` and the key file. To rotate the CI key, generate one with `age-keygen`, put its public key in `packaging/apt/ci-age-recipient.txt`, set the secret, and run `make sync-sops-recipients`.

`make sync-sops-recipients` fails if any maintainer's GitHub keys cannot be fetched, so a network error cannot leave the CI key as the only recipient.

Removing a key does not revoke it: that key already could decrypt the signing key, and old ciphertext stays in git history. To revoke, generate a new signing key, ship its public half in `packaging/apt/reverse-bin-archive-keyring.asc` in a release still signed with the old key, and sign only later releases with the new one.

`gh release create` refuses an existing release. If only the `pages` job failed, rerun just that job. To rerun the whole tag build, delete the release first: `gh release delete vX.Y.Z -y` (the tag stays).

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
