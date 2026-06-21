#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/packaging/debian/logs-app"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$APP/.env" ] || fail "logs app .env missing"
[ -f "$APP/Caddyfile" ] || fail "logs app Caddyfile missing"
[ -f "$APP/setup.sh" ] || fail "logs app setup.sh missing"
[ -f "$APP/README.md" ] || fail "logs app README.md missing"
[ ! -e "$APP/launch.sh" ] || fail "logs app must not ship launch.sh"
[ ! -e "$APP/bin/goaccess" ] || fail "logs app must not ship bin/goaccess"

grep -qx 'REVERSE_BIN_COMMAND=reverse-bin-caddy run --config Caddyfile --adapter caddyfile' "$APP/.env" || fail "REVERSE_BIN_COMMAND must be inline Caddy run"
grep -qx 'REVERSE_BIN_HOST=127.0.0.1' "$APP/.env" || fail ".env must set REVERSE_BIN_HOST"
grep -qx 'REVERSE_BIN_PORT=' "$APP/.env" || fail ".env must request allocated port"
grep -qx 'REVERSE_BIN_HEALTH_METHOD=GET' "$APP/.env" || fail ".env must set health method"
grep -qx 'REVERSE_BIN_HEALTH_PATH=/health' "$APP/.env" || fail ".env must set health path"
! grep -q '^LOGS_BASIC_AUTH_HASH=' "$APP/.env" || fail ".env must not ship LOGS_BASIC_AUTH_HASH"
! grep -q '^LOGS_BASIC_AUTH_PASSWORD=' "$APP/.env" || fail ".env must not ship plaintext password"

grep -qx 'GOACCESS_VERSION=v1\.10\.2' "$ROOT/packaging/runtime-versions.env" || fail "runtime versions must pin GoAccess v1.10.2"
grep -q 'allinurl/goaccess' "$ROOT/scripts/update-runtime-versions.sh" || fail "update-runtime-versions must refresh GoAccess"
grep -q 'GOACCESS_VERSION' "$ROOT/scripts/fetch-runtimes.sh" || fail "fetch-runtimes must use GOACCESS_VERSION"
grep -q 'goaccess_ver=' "$ROOT/scripts/check-runtime-versions.sh" || fail "runtime checks must verify GoAccess"
grep -q 'build/goaccess usr/lib/reverse-bin/' "$ROOT/debian/install" || fail "debian/install must install bundled goaccess"

grep -q 'mkdir -p data/html' "$APP/setup.sh" || fail "setup.sh must create data/html"
grep -q 'new WebSocket' "$APP/setup.sh" || fail "setup.sh placeholder must trigger /ws so GoAccess can generate HTML"
! grep -q 'goaccess caddy-logs/access.log' "$APP/setup.sh" || fail "setup.sh must not run GoAccess"
grep -q 'DOMAIN_SUFFIX' "$APP/setup.sh" || fail "setup.sh must read DOMAIN_SUFFIX"
grep -q 'LOGS_WS_URL=.*logs.*DOMAIN_SUFFIX.*/ws' "$APP/setup.sh" || fail "setup.sh must derive LOGS_WS_URL from DOMAIN_SUFFIX"
grep -q '.logs-dashboard-password' "$APP/setup.sh" || fail "setup.sh must create/use dashboard password file"
grep -q 'CUSTOM_PASSWORD' "$APP/setup.sh" || fail "setup.sh must accept custom password argument"
grep -q 'chmod 600' "$APP/setup.sh" || fail "setup.sh must chmod password file 0600"
grep -q 'hash-password' "$APP/setup.sh" || fail "setup.sh must precompute Caddy auth hash"
grep -q 'LOGS_BASIC_AUTH_HASH=' "$APP/setup.sh" || fail "setup.sh must write LOGS_BASIC_AUTH_HASH"
grep -q 'user: admin' "$APP/setup.sh" || fail "setup.sh must print admin login"
grep -q 'password: cat $PASSWORD_FILE' "$APP/setup.sh" || fail "setup.sh must print local password source"

grep -q 'handle /health' "$APP/Caddyfile" || fail "Caddyfile must leave /health open"
grep -q 'admin {$LOGS_BASIC_AUTH_HASH}' "$APP/Caddyfile" || fail "Caddyfile must use admin with precomputed hash"
grep -q '/usr/lib/reverse-bin/goaccess' "$APP/Caddyfile" || fail "Caddyfile must use bundled GoAccess binary"
grep -q -- '--ws-url={\$LOGS_WS_URL}' "$APP/Caddyfile" || fail "Caddyfile must use configured LOGS_WS_URL"
grep -q 'reverse-bin' "$APP/Caddyfile" || fail "Caddyfile must use reverse-bin to supervise GoAccess"
grep -q 'reverse_proxy_to unix/data/goaccess.sock' "$APP/Caddyfile" || fail "Caddyfile must proxy websocket to GoAccess unix socket"
! grep -q './bin/goaccess' "$APP/Caddyfile" || fail "Caddyfile must not use app-local GoAccess binary"

grep -q 'run `./setup.sh`' "$APP/README.md" || fail "logs README must mention setup.sh"
grep -q 'user `admin`' "$APP/README.md" || fail "logs README must mention admin user"
grep -q './setup.sh '\''your-password-here'\''' "$APP/README.md" || fail "logs README must document custom password setup"
grep -q 'cat /var/lib/reverse-bin/apps/logs/.logs-dashboard-password' "$APP/README.md" || fail "logs README must mention password file"

grep -q 'packaging/debian/logs-app/.env usr/share/reverse-bin/logs-app/' "$ROOT/debian/install" || fail "debian/install must install logs .env"
grep -q 'packaging/debian/logs-app/setup.sh usr/share/reverse-bin/logs-app/' "$ROOT/debian/install" || fail "debian/install must install logs setup.sh"
grep -q 'usr/share/reverse-bin/logs-app' "$ROOT/debian/postinst" || fail "postinst must seed logs app from sample"
grep -q '/var/lib/reverse-bin/apps/logs/caddy-logs' "$ROOT/debian/postinst" || fail "postinst must create logs caddy-logs dir"
grep -q '/var/lib/reverse-bin/apps/logs/caddy-logs' "$ROOT/packaging/debian/reverse-bin.conf" || fail "tmpfiles must create logs caddy-logs dir"
grep -q 'Logging dashboard' "$ROOT/README.md" || fail "main README must document logging dashboard"
grep -q '/var/lib/reverse-bin/apps/logs/README.md' "$ROOT/README.md" || fail "main README must link logs README"

echo "logs app layout checks passed"
