#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CADDY="$ROOT/build/reverse-bin-caddy"
GOACCESS="$ROOT/build/goaccess"
WEBSOCAT="$ROOT/build/test-tools/websocat"
APP_SRC="$ROOT/packaging/debian/logs-app"

[ -x "$CADDY" ] || { echo "missing $CADDY" >&2; exit 1; }
[ -x "$GOACCESS" ] || { echo "missing $GOACCESS" >&2; exit 1; }
[ -x "$WEBSOCAT" ] || { echo "missing $WEBSOCAT" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/logs-app-smoke.XXXXXX")
cleanup() {
  if [ -n "${CADDY_PID:-}" ]; then
    kill "$CADDY_PID" 2>/dev/null || true
    wait "$CADDY_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

cp -a "$APP_SRC/." "$TMP/"
cd "$TMP"
CUSTOM_PASSWORD='user-chosen-test-password'
PATH="$ROOT/build:$PATH" DOMAIN_SUFFIX=example.test ./setup.sh "$CUSTOM_PASSWORD" > setup.out
[ -f .logs-dashboard-password ] || { echo "password file missing" >&2; exit 1; }
[ "$(tr -d '\r\n' < .logs-dashboard-password)" = "$CUSTOM_PASSWORD" ] || { echo "custom password not stored" >&2; exit 1; }
grep -q 'GoAccess dashboard initializing' data/html/index.html || { echo "setup placeholder missing" >&2; exit 1; }
grep -q '^LOGS_BASIC_AUTH_HASH=' .env || { echo "auth hash missing" >&2; exit 1; }
grep -q 'user: admin' setup.out || { echo "setup output missing admin" >&2; exit 1; }
grep -q 'cat .*/.logs-dashboard-password' setup.out || { echo "setup output missing password source" >&2; exit 1; }
grep -q '^LOGS_WS_URL=logs.example.test/ws' .env || { echo "LOGS_WS_URL missing" >&2; exit 1; }

PORT=$(python3 - <<'PY'
import socket
s=socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
)
HASH=$(awk -F= '/^LOGS_BASIC_AUTH_HASH=/{print $2}' .env)
LOGS_WS_URL=$(awk -F= '/^LOGS_WS_URL=/{print $2}' .env)
LOGS_WS_PORT=$(awk -F= '/^LOGS_WS_PORT=/{print $2}' .env)
PASSWORD=$(tr -d '\r\n' < .logs-dashboard-password)
AUTH=$(printf 'admin:%s' "$PASSWORD" | base64 | tr -d '\n')

REVERSE_BIN_HOST=127.0.0.1 \
REVERSE_BIN_PORT="$PORT" \
LOGS_BASIC_AUTH_HASH="$HASH" \
LOGS_WS_URL="$LOGS_WS_URL" \
LOGS_WS_PORT="$LOGS_WS_PORT" \
GOACCESS_BIN="$GOACCESS" \
"$CADDY" run --config Caddyfile --adapter caddyfile > caddy.out 2>&1 &
CADDY_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health")
[ "$code" = 200 ] || { echo "/health got $code" >&2; exit 1; }
code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/")
[ "$code" = 401 ] || { echo "/ without auth got $code" >&2; exit 1; }
code=$(curl -sS -u "admin:$PASSWORD" -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/")
[ "$code" = 200 ] || { echo "/ with auth got $code" >&2; exit 1; }

append_log() {
  ts=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  cat >> caddy-logs/access.log <<EOF
{"level":"info","ts":$ts,"logger":"http.log.access.log0","msg":"handled request","request":{"remote_ip":"127.0.0.1","remote_port":"12345","client_ip":"127.0.0.1","proto":"HTTP/1.1","method":"GET","host":"logs.local","uri":"/smoke-$ts","headers":{"User-Agent":["smoke"],"Accept":["*/*"]}},"bytes_read":0,"user_id":"","duration":0.001,"size":2,"status":200,"resp_headers":{"Server":["Caddy"],"Content-Type":["text/plain"]}}
EOF
}

append_log
WS_OUT="$TMP/ws.out"
WS_ERR="$TMP/ws.err"
( timeout 5 "$WEBSOCAT" -H="Authorization: Basic $AUTH" "ws://127.0.0.1:$PORT/ws" > "$WS_OUT" 2> "$WS_ERR" || true ) &
WS_PID=$!
sleep 2
append_log
sleep 1
kill "$WS_PID" 2>/dev/null || true
wait "$WS_PID" 2>/dev/null || true

grep -q 'started proxy subprocess' caddy.out || { echo "GoAccess did not start from /ws" >&2; cat "$WS_ERR" >&2; cat caddy.out >&2; exit 1; }
for _ in 1 2 3 4 5; do
  [ -s data/html/index.html ] && break
  sleep 0.5
done
[ -s data/html/index.html ] || { echo "GoAccess did not write data/html/index.html" >&2; cat "$WS_ERR" >&2; cat caddy.out >&2; exit 1; }
grep -q '<!DOCTYPE html>' data/html/index.html || { echo "GoAccess did not generate HTML" >&2; cat "$WS_ERR" >&2; cat caddy.out >&2; exit 1; }
code=$(curl -sS -u "admin:$PASSWORD" -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/")
[ "$code" = 200 ] || { echo "/ with auth after GoAccess got $code" >&2; exit 1; }

echo "logs app smoke passed"
