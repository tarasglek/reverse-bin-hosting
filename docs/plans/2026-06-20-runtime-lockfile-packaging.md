# Runtime Lockfile Packaging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make this repository assemble a Debian package from pinned latest-stable runtime versions with coherent local and CI caching.

**Architecture:** `packaging/runtime-versions.env` is the checked-in source of truth. `scripts/update-runtime-versions.sh` refreshes it from upstream latest stable release metadata. `scripts/fetch-runtimes.sh` downloads or builds pinned runtimes into `${XDG_CACHE_HOME:-$HOME/.cache}/reverse-bin-hosting/runtimes/<tool>/<version>/<os>-<arch>/`, copies them into `build/`, and verifies versions before packaging. GitHub Actions caches that runtime cache keyed by the lockfile.

**Tech Stack:** GNU Make, Debian debhelper, POSIX shell, GitHub release APIs via `curl`, Go/xcaddy, GitHub Actions cache, existing Python tests.

---

## Tasks

1. Add `packaging/runtime-versions.env` with pinned latest-stable versions for the Caddy plugin, `uv`, `landrun`, `deno`, `sops`, and `age`.
2. Update `Makefile` and `debian/rules` to source the lockfile.
3. Add `scripts/update-runtime-versions.sh` to refresh the lockfile from upstream stable releases.
4. Add `scripts/fetch-runtimes.sh` to populate the Linux user cache directory, copy runtime binaries into `build/`, and avoid repeated downloads locally or in CI.
5. Add `scripts/check-runtime-versions.sh` to validate `build/` binaries against the lockfile. For `landrun`, validate the Go module version instead of the CLI-reported version because upstream `v0.1.14` still prints `0.1.13`.
6. Add GitHub Actions packaging workflow with Go cache and runtime cache keyed by `packaging/runtime-versions.env`.
7. Update README runtime lockfile docs.
8. Delete repo-review findings 1 and 2 after verification.
9. Verify with `make update-runtime-versions`, `make fetch-runtimes`, `make build`, `make tests`, and `git diff --check`.
