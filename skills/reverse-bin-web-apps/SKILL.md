---
name: reverse-bin-web-apps
description: Use when writing or debugging web apps that might run under reverse-bin-hosting, reverse-bin app directories, nested Caddy apps, access logs, Cloudflare-fronted logs, or GoAccess dashboards.
---

# Reverse-Bin Web Apps

## Overview

Reverse-bin serves apps from an app root, normally `/var/lib/reverse-bin/apps`. In this skill, `APP_ROOT` means that app root. Each app lives in `APP_ROOT/<app-name>`, for example `APP_ROOT/my-app`. Apps are served by the outer `reverse-bin` Caddy using hostnames like `<app>.$DOMAIN_SUFFIX`.

Packaged installs also place this skill under `APP_ROOT/skills/reverse-bin-web-apps/SKILL.md`. Symlinking the global agent skill to that installed copy is a good way to keep agent guidance in sync with the installed reverse-bin package.

The app root may be mounted elsewhere for editing or deployment. For example, operators can bind-mount `/var/lib/reverse-bin/apps` to a user-editable directory, including with UID/GID remapping so non-root users can manage app files while the service still sees the canonical app paths.

Before writing or debugging any web app, verify whether it is actually a reverse-bin app. This matters because reverse-bin changes app layout, writable paths, runtime environment, sandboxing, health checks, and proxy behavior. Do not assume a user-writable directory is ordinary source: check whether its directory is a symlink into the reverse-bin app root, a bind mount of `/var/lib/reverse-bin/apps`, or a UID/GID-remapped mount that presents reverse-bin app files as user-writable.

## Security Posture Reference

Packaged installs include the current isolation model and verification checklist at `/usr/share/doc/reverse-bin/SECURITY-POSTURE.md`.

## Most Ergonomic Defaults

Reverse-bin aims to be runtime-neutral: any well-behaved app can work if it follows the app layout, writable-state, health-check, and bind/socket rules.

For new apps, prefer a self-contained app directory with its own `.git` repository so the app can be deployed with `git push`. Set up the bare/deploy repo so pushes unpack or check out into the reverse-bin app directory.

Most ergonomic current defaults:

- Deno app with `export default` entrypoint; detector runs discovered Deno apps in watch mode, so source edits restart the app.
- Hono for HTTP routing.
- `https://jsr.io/@tarasglek/locker` when app-level auth is needed.
- SOPS + `github-to-sops` when secrets are needed.
- Keep runtime state in `data/`; keep source/config in the app repo.

Well-behaved Go apps also work well, especially when they support Unix sockets. GoAccess is a good example: it can serve over a Unix socket, while Deno is still waiting on Unix socket listener support: https://github.com/denoland/deno/pull/32094

## App Layouts

### Static app

```text
APP_ROOT/my-app/index.html
```

Reverse-bin detects `index.html` and serves it with nested Caddy over a reverse-bin-managed Unix socket at `/run/reverse-bin/static-apps/app-<hash>/reverse-bin.sock`. Static apps cannot configure `SOCKET_PATH` or TCP listeners.

### Command app

```text
APP_ROOT/my-app/.env
APP_ROOT/my-app/launch.sh
APP_ROOT/my-app/data/
```

`.env` example:

```sh
REVERSE_BIN_COMMAND=./launch.sh
REVERSE_BIN_HOST=127.0.0.1
REVERSE_BIN_PORT=
REVERSE_BIN_HEALTH_METHOD=GET
REVERSE_BIN_HEALTH_PATH=/health
```

`launch.sh` must use `data/` for writable state. Prefer Unix sockets when the app/runtime supports them; otherwise bind TCP to `$REVERSE_BIN_HOST:$REVERSE_BIN_PORT`.

## Nested Caddy Pattern

Use this when an app needs static files plus proxy routes:

```caddy
{
	admin off
	auto_https off
}

http://:{$REVERSE_BIN_PORT} {
	bind {$REVERSE_BIN_HOST}

	handle /health {
		respond "ok" 200
	}

	root * data
	file_server
}
```

Important: do **not** use `http://{$REVERSE_BIN_HOST}:{$REVERSE_BIN_PORT}`. That matches only `Host: 127.0.0.1:$PORT`; outer reverse-bin forwards the public host, causing empty `200` responses.

## Writable vs Read-only Paths

- App source is mounted read-only in the sandbox.
- For non-static apps, `data/` is writable when present.
- Static apps receive only their managed `/run/reverse-bin/static-apps/app-<hash>/` socket directory as writable; their app `data/` remains read-only.
- `HOME` defaults to `APP_ROOT/<app-name>/data` when the app does not define `HOME` itself.
- Keep runtime state in `data/`: databases, uploads, generated assets, temp files, package-manager caches, managed toolchains, virtualenvs, lockfiles created at runtime, sockets, FIFOs, and Caddy state.
- If a runtime ignores `HOME`, set its cache/data variables explicitly in `.env`, `secrets.enc.json`, or `launch.sh` so it writes under `data/`.
- Read-only source/config inputs can live elsewhere in the app directory.

## Unix Sockets

Prefer Unix sockets when the app/runtime supports them. They avoid race-prone free-port selection, make launches more deterministic, and require no TCP bind permission. App-managed sockets belong under `data/` so they are writable inside the sandbox; static Caddy sockets are managed separately under `/run/reverse-bin/static-apps/`.

Nested Caddy file-server accepts absolute Unix socket listeners such as `--listen unix///absolute/path.sock`. Landrun only permits TCP bind on `$REVERSE_BIN_PORT`; Unix socket transports need no `--bind-tcp`. For helper services needing a second listener, use Unix sockets under `data/`.

Caddy proxy example:

```caddy
handle /ws* {
	reverse_proxy unix///absolute/path/to/app/data/service.sock
}
```

Use three slashes after `unix:` for absolute paths.

## Secrets with SOPS

Apps may use plaintext `.env` or encrypted `secrets.enc.json`, not both. `reverse-bin-detector` rejects app directories containing both files to avoid ambiguous secrets.

The default app root is `/var/lib/reverse-bin/apps`; package install creates `/var/lib/reverse-bin/keys/age.key`, `/var/lib/reverse-bin/keys/age.pub`, and seeds `APP_ROOT/.sops.yaml` with the server age recipient. For app checkouts elsewhere, create a local `.sops.yaml` that includes the server age recipient plus the editor's SSH/GitHub recipient. Prefer `github-to-sops` for GitHub-managed SSH keys so authorized deploy/edit users can be managed from GitHub keys.

Convert dotenv secrets to encrypted JSON, then remove plaintext only after encryption succeeds:

```sh
sops --encrypt --input-type dotenv --output-type json --filename-override secrets.enc.json .env > secrets.enc.json && rm .env
```

At runtime, systemd sets `SOPS_AGE_KEY_FILE=/var/lib/reverse-bin/keys/age.key`. The detector decrypts `secrets.enc.json` in memory with bundled SOPS, passes parsed dotenv values to the child app, and keeps the private key outside app directories. Child apps only receive `SOPS_AGE_KEY_FILE` if the app env explicitly defines it.

## Logs / GoAccess Dashboard

The default Debian install seeds a `logs` app at `APP_ROOT/logs`. Packaged outer Caddy configs write JSON access logs to `APP_ROOT/logs/caddy-logs/access.log`, and the seeded app uses bundled GoAccess to render the dashboard.

The logs app is not active until credentials are generated:

```sh
cd /var/lib/reverse-bin/apps/logs
./setup.sh
```

Login user is `admin`; setup stores the password in `APP_ROOT/logs/.logs-dashboard-password`. In the packaged Cloudflare-fronted HTTP-only config, outer Caddy is already configured to trust the local proxy so logs contain the real visitor IP in `request.client_ip`.

## Debug Checklist

Prefer debugging through the same public app URL users hit. Direct app access bypasses reverse-bin behavior and should be a last resort.

1. Test the public app domain:
   ```sh
   curl -i https://my-app.$DOMAIN_SUFFIX/
   ```
2. Check reverse-bin/Caddy logs for launch, health, proxy, and access-log behavior. Also check the default Caddy JSON access log that feeds the GoAccess app: `APP_ROOT/logs/caddy-logs/access.log`.
   ```sh
   sudo journalctl -u reverse-bin.service --since '5 minutes ago' --no-pager
   sudo tail -f /var/lib/reverse-bin/apps/logs/caddy-logs/access.log
   ```
3. If the app is running but proxy behavior is wrong, check nested Caddy host matchers and health routes. Empty `200` responses often mean an inner Caddy used `http://{$REVERSE_BIN_HOST}:{$REVERSE_BIN_PORT}` instead of `http://:{$REVERSE_BIN_PORT}` plus `bind {$REVERSE_BIN_HOST}`.
4. For WebSockets, verify upgrade through the public app domain:
   ```sh
   curl -i --http1.1 -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
     -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
     -H 'Sec-WebSocket-Version: 13' https://my-app.$DOMAIN_SUFFIX/ws
   ```
   Expected: `101 Switching Protocols`.
5. Last resort only: reproduce locally through the detector/reverse-bin path, not by manually running the app. Use `utils/run-reverse-bin-app.sh APP_ROOT/my-app` or the packaged equivalent so `reverse-bin-detector`, sandbox policy, env loading, health checks, and proxy supervision are still involved. This is comparable to production when run against the same app tree, especially a symlink/bind/UID-remapped mount of `APP_ROOT`. Only after that, inspect the spawned inner port/socket from logs if you must isolate an app bug.
