# Logs dashboard app

Packaged reverse-bin logging dashboard sample.

## Setup

After package install, app files are seeded at `/var/lib/reverse-bin/apps/logs/` but auth is not active yet.

run `./setup.sh` from `/var/lib/reverse-bin/apps/logs/`:

```sh
cd /var/lib/reverse-bin/apps/logs
./setup.sh
```

To choose the dashboard password yourself:

```sh
./setup.sh 'your-password-here'
```

Login user `admin`.

Password is stored locally:

```sh
cat /var/lib/reverse-bin/apps/logs/.logs-dashboard-password
```

## Architecture

- Outer reverse-bin Caddy writes JSON access logs to `caddy-logs/access.log`.
- Inner Caddy serves `/health` without auth.
- Inner Caddy protects `/` and `/ws*` with Basic auth.
- `/` serves generated GoAccess HTML from `data/html/`.
- `/ws*` uses the Caddy `reverse-bin` plugin to start bundled `/usr/lib/reverse-bin/goaccess` on demand.
- GoAccess reads `caddy-logs/access.log` with `--log-format=CADDY`, writes HTML under `data/html/`, and exposes realtime WebSocket updates on `data/goaccess.sock`.

Keep raw logs in `caddy-logs/`. Keep generated public files under `data/html/`. Keep sockets and FIFOs directly under `data/`, outside web root.
