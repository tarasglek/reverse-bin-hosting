#!/usr/bin/env sh
set -eu

usage() {
  echo "Usage: $0 APP_DIR [PORT]" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_DIR_INPUT=$1
PORT=${2:-9443}

case "$APP_DIR_INPUT" in
  /*) APP_DIR=$APP_DIR_INPUT ;;
  *) APP_DIR=$(CDPATH= cd -- "$APP_DIR_INPUT" && pwd) ;;
esac

if [ ! -d "$APP_DIR" ]; then
  echo "APP_DIR does not exist: $APP_DIR" >&2
  exit 1
fi

case "$PORT" in
  ''|*[!0-9]*)
    echo "PORT must be numeric: $PORT" >&2
    exit 2
    ;;
esac

TEMP_CADDYFILE=$(mktemp "${TMPDIR:-/tmp}/reverse-bin-app.XXXXXX.caddy")
cleanup() {
  rm -f "$TEMP_CADDYFILE"
}
trap cleanup EXIT INT TERM

# Apps are always served as https://$REVERSE_BIN_PUBLIC_HOST, so local runs use Caddy's internal CA too.
APP_NAME=$(basename "$APP_DIR" | tr 'A-Z_.' 'a-z--')
cat > "$TEMP_CADDYFILE" <<EOF
{
	admin off
	skip_install_trust
	auto_https disable_redirects
}

https://$APP_NAME.localhost:$PORT {
	bind 127.0.0.1
	tls internal
	reverse-bin {
		dynamic_proxy_detector $REPO_ROOT/build/reverse-bin-detector --public-host=$APP_NAME.localhost:$PORT $APP_DIR
		health_check HEAD /
		idle_timeout_ms 300000
		health_timeout_ms 15000
		termination_grace_ms 5000
		termination_kill_wait_ms 1000
	}
}
EOF

CADDY_BIN="$REPO_ROOT/build/reverse-bin-caddy"
DETECTOR_BIN="$REPO_ROOT/build/reverse-bin-detector"
if [ ! -x "$CADDY_BIN" ] || [ ! -x "$DETECTOR_BIN" ]; then
  (cd "$REPO_ROOT" && make build fetch-runtimes)
fi

printf 'reverse-bin app runner\n  app: %s\n  url: https://%s.localhost:%s/\n  ca: %s\n  caddyfile: %s\n  caddy: %s\n' "$APP_DIR" "$APP_NAME" "$PORT" "${XDG_DATA_HOME:-$HOME/.local/share}/caddy/pki/authorities/local/root.crt" "$TEMP_CADDYFILE" "$CADDY_BIN" >&2

exec "$CADDY_BIN" run --adapter caddyfile --config "$TEMP_CADDYFILE"
