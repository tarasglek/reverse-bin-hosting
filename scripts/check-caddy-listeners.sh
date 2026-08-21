#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CADDY_BIN=${CADDY_BIN:-$ROOT/build/reverse-bin-caddy}

fail() {
    echo "error: $*" >&2
    exit 1
}

assert_port_listener() {
    config=$1
    port=$2
    want=$3

    # Adapt the real packaged config so host matchers cannot masquerade as listener isolation.
    got=$(OPS_EMAIL=ops@example.test DOMAIN_SUFFIX=example.test REVERSE_BIN_HTTP_PORT=7777 \
        "$CADDY_BIN" adapt --adapter caddyfile --config "$config" 2>/dev/null |
        python3 -c '
import json
import sys

port = sys.argv[1]
config = json.load(sys.stdin)
servers = config.get("apps", {}).get("http", {}).get("servers", {})
listeners = sorted(
    address
    for server in servers.values()
    for address in server.get("listen", [])
    if address.endswith(":" + port)
)
print("\n".join(listeners))
' "$port")

    [ "$got" = "$want" ] || fail "$config port $port listeners = [$got], want exactly [$want]"
}

# Verify the generated development Caddyfile also binds its default port to loopback.
python3 - "$ROOT/utils/run-reverse-bin-app.sh" <<'PY'
import pathlib
import sys

script = pathlib.Path(sys.argv[1])
text = script.read_text()
want = "http://127.0.0.1:$HTTP_PORT {\n\tbind 127.0.0.1\n"
if want not in text:
    raise SystemExit(f"error: {script} does not bind its generated listener to IPv4 loopback")
PY

assert_port_listener "$ROOT/packaging/debian/Caddyfile.acme" 9080 127.0.0.1:9080
assert_port_listener "$ROOT/packaging/debian/Caddyfile.http-only" 7777 127.0.0.1:7777

echo "packaged Caddy listeners are loopback-only"
