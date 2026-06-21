# Logs Sample App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a default `logs` app sample that exists after dpkg install but stays inactive until `setup.sh` downloads GoAccess and writes auth config.

**Architecture:** Debian package installs sample files under `/usr/share/reverse-bin/logs-app/` and seeds `/var/lib/reverse-bin/apps/logs/` on install without overwriting local changes. `setup.sh` prepares runtime-only pieces: `data/html`, app-local `bin/goaccess`, and `LOGS_BASIC_AUTH_HASH` computed from `/var/lib/reverse-bin/keys/age.pub`. The app runs inner Caddy directly from inline `REVERSE_BIN_COMMAND`.

**Tech Stack:** Debian packaging, POSIX shell, Caddyfile, GoAccess v1.10.2, reverse-bin explicit command apps.

---

## Lazy Human Review Checklist

- [ ] dpkg creates `/var/lib/reverse-bin/apps/logs/caddy-logs/` for outer Caddy JSON logs.
- [ ] dpkg seeds `/var/lib/reverse-bin/apps/logs/` sample app files.
- [ ] Sample app ships no `bin/goaccess` binary.
- [ ] Sample app ships no `launch.sh`.
- [ ] `.env` uses inline command: `reverse-bin-caddy run --config Caddyfile --adapter caddyfile`.
- [ ] `.env` ships without `LOGS_BASIC_AUTH_HASH` and without plaintext password.
- [ ] `setup.sh` pins GoAccess `1.10.2`.
- [ ] `setup.sh` downloads/builds or installs app-local `bin/goaccess`.
- [ ] `setup.sh` creates `data/html`.
- [ ] `setup.sh` reads password from `/var/lib/reverse-bin/keys/age.pub`.
- [ ] `setup.sh` precomputes Caddy hash and writes `LOGS_BASIC_AUTH_HASH=...` into `.env`.
- [ ] Caddy protects `/` and `/ws*` with username `admin` and `{$LOGS_BASIC_AUTH_HASH}`.
- [ ] Caddy leaves `/health` open.
- [ ] Main `README.md` has Logging dashboard section and links `/var/lib/reverse-bin/apps/logs/README.md`.
- [ ] Logs app `README.md` says: run `./setup.sh`; login user `admin`; password is `cat /var/lib/reverse-bin/keys/age.pub`.
- [ ] Verification covers package layout, Caddyfile syntax, and auth behavior.

## Task 1: Add Package Layout Test

**Files:**
- Create/modify: `scripts/check-logs-app.sh`

**Steps:**
1. Write shell check for sample files, missing `launch.sh`, missing `bin/goaccess`, `.env` inline command, no shipped auth, setup version/hash behavior, Caddy auth, README links.
2. Run: `scripts/check-logs-app.sh`
3. Expected: FAIL before implementation.
4. Commit after pass later: `test(packaging): check logs sample app layout`.

## Task 2: Add Logs Sample App

**Files:**
- Create: `packaging/debian/logs-app/.env`
- Create: `packaging/debian/logs-app/Caddyfile`
- Create: `packaging/debian/logs-app/setup.sh`
- Create: `packaging/debian/logs-app/README.md`

**Steps:**
1. Add `.env` with inline Caddy command and health config only.
2. Add nested Caddy with `/health`, `/ws*`, static root, basic auth user `admin`.
3. Add `setup.sh` that pins GoAccess 1.10.2, installs `bin/goaccess`, creates `data/html`, hashes age.pub into `.env`.
4. Add logs app README.
5. Run: `scripts/check-logs-app.sh`
6. Expected: PASS.

## Task 3: Wire Debian Package Install

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

## Task 4: Document Logging Dashboard

**Files:**
- Modify: `README.md`

**Steps:**
1. Add `## Logging dashboard` near runtime/deployment docs.
2. Explain outer Caddy JSON log target.
3. Explain sample app exists by default but needs `/var/lib/reverse-bin/apps/logs/setup.sh`.
4. Link `/var/lib/reverse-bin/apps/logs/README.md` for details.
5. Run: `scripts/check-logs-app.sh`.
6. Expected: PASS.

## Task 5: Reset Existing Logs App Before Package Test

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
5. Verify fresh `/var/lib/reverse-bin/apps/logs` contains package sample only: no `bin/goaccess`, no `LOGS_BASIC_AUTH_HASH`.

## Task 6: Verify Runtime Behavior

**Commands:**
```sh
cd /var/lib/reverse-bin/apps/logs
./setup.sh
reverse-bin-caddy validate --config Caddyfile --adapter caddyfile
curl -i http://127.0.0.1:$PORT/health
curl -i http://127.0.0.1:$PORT/
curl -i -u "admin:$(cat /var/lib/reverse-bin/keys/age.pub)" http://127.0.0.1:$PORT/
```

**Expected:**
- Caddyfile validates.
- `/health` returns `200` without auth.
- `/` returns `401` without auth.
- `/` returns `200` with `admin:<age.pub>`.
