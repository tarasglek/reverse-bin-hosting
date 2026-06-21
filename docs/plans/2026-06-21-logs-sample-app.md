# Logs Sample App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a default `logs` app sample that exists after dpkg install but stays inactive until `setup.sh` writes auth config.

**Architecture:** Debian package bundles GoAccess with other reverse-bin runtime binaries. Package installs sample files under `/usr/share/reverse-bin/logs-app/` and seeds `/var/lib/reverse-bin/apps/logs/` on install without overwriting local changes. `setup.sh` only creates needed app data dirs, computes `LOGS_BASIC_AUTH_HASH` from `/var/lib/reverse-bin/keys/age.pub`, updates `.env`, and prints login instructions.

**Tech Stack:** Debian packaging, POSIX shell, Caddyfile, bundled GoAccess v1.10.2, test-only websocat, reverse-bin explicit command apps.

---

## Lazy Human Review Checklist

- [ ] dpkg creates `/var/lib/reverse-bin/apps/logs/caddy-logs/` for outer Caddy JSON logs.
- [ ] dpkg seeds `/var/lib/reverse-bin/apps/logs/` sample app files.
- [ ] Debian package bundles GoAccess with other runtime binaries.
- [ ] Sample app ships no `bin/goaccess` binary.
- [ ] Sample app ships no `launch.sh`.
- [ ] `.env` uses inline command: `reverse-bin-caddy run --config Caddyfile --adapter caddyfile`.
- [ ] `.env` ships without `LOGS_BASIC_AUTH_HASH` and without plaintext password.
- [ ] GoAccess version pinned to `v1.10.2` in runtime version config.
- [ ] `setup.sh` does not download GoAccess.
- [ ] `setup.sh` creates `data/html`.
- [ ] `setup.sh` reads password from `/var/lib/reverse-bin/keys/age.pub`.
- [ ] `setup.sh` precomputes Caddy hash and writes `LOGS_BASIC_AUTH_HASH=...` into `.env`.
- [ ] `setup.sh` prints login instructions: user `admin`, password source `/var/lib/reverse-bin/keys/age.pub`.
- [ ] Caddy uses bundled `/usr/lib/reverse-bin/goaccess`.
- [ ] Caddy protects `/` and `/ws*` with username `admin` and `{$LOGS_BASIC_AUTH_HASH}`.
- [ ] Caddy leaves `/health` open.
- [ ] Main `README.md` has Logging dashboard section and links `/var/lib/reverse-bin/apps/logs/README.md`.
- [ ] Logs app `README.md` says: run `./setup.sh`; login user `admin`; password is `cat /var/lib/reverse-bin/keys/age.pub`.
- [ ] Test tooling pulls test-only `websocat`.
- [ ] Smoke test verifies setup, auth, WebSocket upgrade, and realtime GoAccess output.

## Task 1: Add Package Layout Test

**Files:**
- Create/modify: `scripts/check-logs-app.sh`

**Steps:**
1. Write shell check for sample files, missing `launch.sh`, missing app-local `bin/goaccess`, `.env` inline command, no shipped auth, bundled GoAccess version, setup hash behavior, setup login output, Caddy auth, README links.
2. Run: `scripts/check-logs-app.sh`.
3. Expected: FAIL before implementation.
4. Commit after pass later: `test(packaging): check logs sample app layout`.

## Task 2: Bundle GoAccess Runtime

**Files:**
- Modify: `packaging/runtime-versions.env`
- Modify: `scripts/fetch-runtimes.sh`
- Modify: `scripts/check-runtime-versions.sh`
- Modify: `debian/install`

**Steps:**
1. Add `GOACCESS_VERSION=v1.10.2` to runtime versions.
2. Extend runtime fetch to install `build/goaccess` from pinned GoAccess release/build.
3. Verify `build/goaccess --version` reports `GoAccess - 1.10.2`.
4. Install `build/goaccess usr/lib/reverse-bin/`.
5. Run runtime version checks.
6. Commit: `feat(packaging): bundle goaccess runtime`.

## Task 3: Add Logs Sample App

**Files:**
- Create: `packaging/debian/logs-app/.env`
- Create: `packaging/debian/logs-app/Caddyfile`
- Create: `packaging/debian/logs-app/setup.sh`
- Create: `packaging/debian/logs-app/README.md`

**Steps:**
1. Add `.env` with inline Caddy command and health config only.
2. Add nested Caddy with `/health`, `/ws*`, static root, basic auth user `admin`.
3. Point GoAccess command at `/usr/lib/reverse-bin/goaccess`.
4. Add `setup.sh` that creates `data/html`, hashes age.pub into `.env`, and prints login instructions.
5. Add logs app README.
6. Run: `scripts/check-logs-app.sh`.
7. Expected: PASS.

## Task 4: Wire Debian Package Install

**Files:**
- Modify: `debian/install`
- Modify: `debian/postinst`
- Modify: `packaging/debian/reverse-bin.conf`

**Steps:**
1. Install logs sample files into `/usr/share/reverse-bin/logs-app/`.
2. In `postinst`, seed missing files into `/var/lib/reverse-bin/apps/logs/` without overwriting changed local files.
3. Ensure tmpfiles creates `/var/lib/reverse-bin/apps/logs/caddy-logs/`.
4. Run: `scripts/check-logs-app.sh`.
5. Expected: PASS.

## Task 5: Document Logging Dashboard

**Files:**
- Modify: `README.md`

**Steps:**
1. Add `## Logging dashboard` near runtime/deployment docs.
2. Explain outer Caddy JSON log target.
3. Explain sample app exists by default but needs `/var/lib/reverse-bin/apps/logs/setup.sh` for credentials.
4. Link `/var/lib/reverse-bin/apps/logs/README.md` for details.
5. Run: `scripts/check-logs-app.sh`.
6. Expected: PASS.

## Task 6: Reset Existing Logs App Before Package Test

**Files:**
- Existing runtime path: `/var/lib/reverse-bin/apps/logs`
- Editable mirror if present: `/home/taras/smallweb/logs`

**Steps:**
1. Stop `reverse-bin.service` if testing on live host.
2. Back up existing logs app instead of deleting raw logs blindly:
   ```sh
   ts=$(date +%Y%m%d%H%M%S)
   sudo mv /var/lib/reverse-bin/apps/logs "/var/lib/reverse-bin/apps/logs.backup.$ts"
   ```
3. If `/home/taras/smallweb/logs` is a separate editable tree, move it too:
   ```sh
   mv /home/taras/smallweb/logs "/home/taras/smallweb/logs.backup.$ts"
   ```
4. Install package so `postinst` seeds fresh defaults.
5. Verify fresh `/var/lib/reverse-bin/apps/logs` contains package sample only: no app-local `bin/goaccess`, no `LOGS_BASIC_AUTH_HASH`; GoAccess exists at `/usr/lib/reverse-bin/goaccess`.

## Task 7: Add Test-Only WebSocket Tooling

**Files:**
- Modify: `packaging/runtime-versions.env`
- Create/modify: `scripts/fetch-test-runtimes.sh`
- Modify: `Makefile`

**Steps:**
1. Add pinned `WEBSOCAT_VERSION` for test tooling only.
2. Add `scripts/fetch-test-runtimes.sh` that downloads `websocat` into `build/test-tools/websocat` using existing runtime cache style.
3. Add Make target `fetch-test-runtimes`.
4. Do not install `websocat` into Debian package.
5. Commit: `test: fetch websocat for smoke tests`.

## Task 8: Add Logs App Realtime Smoke Test

**Files:**
- Create: `scripts/smoke-logs-app.sh`
- Modify: `Makefile`

**Steps:**
1. Build/fetch package runtimes and test runtimes.
2. Use fresh seeded logs app or copied package sample in temp dir.
3. Run `./setup.sh` and assert it prints login instructions.
4. Start inner Caddy with `REVERSE_BIN_HOST=127.0.0.1` and test port.
5. Assert `/health` returns `200` without auth.
6. Assert `/` returns `401` without auth.
7. Assert `/` returns `200` with `admin:$(cat /var/lib/reverse-bin/keys/age.pub)`.
8. Append a valid Caddy JSON access log row to `caddy-logs/access.log`.
9. Connect to `/ws` with `build/test-tools/websocat` using Basic auth header.
10. Assert websocket receives realtime GoAccess data after another log row is appended.
11. Add Make target `smoke-logs-app`.
12. Commit: `test: smoke test logs dashboard realtime websocket`.

**Expected:**
- `setup.sh` prints login instructions.
- Caddyfile validates.
- `/health` open.
- `/` auth works.
- `/ws` accepts authenticated websocket.
- GoAccess emits realtime websocket data when access log grows.
