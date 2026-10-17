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

assert_admin_off() {
    config=$1

    # Sandboxed apps share the host loopback; the admin API would let them reconfigure Caddy.
    OPS_EMAIL=ops@example.test DOMAIN_SUFFIX=example.test REVERSE_BIN_HTTP_PORT=7777 \
        "$CADDY_BIN" adapt --adapter caddyfile --config "$config" 2>/dev/null |
        python3 -c '
import json
import sys

config = json.load(sys.stdin)
sys.exit(0 if config.get("admin", {}).get("disabled") is True else 1)
' || fail "$config must disable the Caddy admin API (admin off)"
}

assert_public_url_map() {
    config=$1

    # reverse-bin keys backend processes on the expanded detector args, so host aliases of
    # one app must expand to the same app dir and public URL or they race for one socket.
    OPS_EMAIL=ops@example.test DOMAIN_SUFFIX=example.test REVERSE_BIN_HTTP_PORT=7777 \
        "$CADDY_BIN" adapt --adapter caddyfile --config "$config" 2>/dev/null |
        python3 -c '
import json
import sys

def walk(node):
    if isinstance(node, dict):
        yield node
        node = list(node.values())
    if isinstance(node, list):
        for child in node:
            yield from walk(child)

config = json.load(sys.stdin)
maps = [n for n in walk(config) if n.get("handler") == "map" and n.get("source") == "{http.request.host}"]
if len(maps) != 1:
    sys.exit(f"want one host map, found {len(maps)}")
m = maps[0]
if m.get("destinations") != ["{reverse_bin_app_dir}", "{reverse_bin_public_url}"]:
    sys.exit(f"map destinations = {m.get("destinations")}")
rows = {row["input"]: row["outputs"] for row in m.get("mappings", [])}
www = ["/var/lib/reverse-bin/apps/www", "https://example.test"]
if rows.get("example.test") != www or rows.get("www.example.test") != www:
    sys.exit(f"apex/www rows = {rows}, want both {www}")
label = "{http.request.host.labels.2}"
want_default = ["/var/lib/reverse-bin/apps/" + label, "https://" + label + ".example.test"]
if m.get("defaults") != want_default:
    sys.exit(f"map defaults = {m.get("defaults")}, want {want_default}")
detectors = [n["dynamic_proxy_detector"] for n in walk(config) if "dynamic_proxy_detector" in n]
want_args = ["--public-url={reverse_bin_public_url}", "{reverse_bin_app_dir}"]
if not detectors or any(d[1:] != want_args for d in detectors):
    sys.exit(f"detector args = {detectors}, want [detector, *{want_args}]")
' || fail "$config must pass one canonical --public-url per app to the detector"
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
if "--public-url=http://127.0.0.1:$HTTP_PORT $APP_DIR" not in text:
    raise SystemExit(f"error: {script} does not pass its local URL to the detector")
PY

assert_port_listener "$ROOT/packaging/debian/Caddyfile.acme" 9080 127.0.0.1:9080
assert_port_listener "$ROOT/packaging/debian/Caddyfile.http-only" 7777 127.0.0.1:7777
assert_admin_off "$ROOT/packaging/debian/Caddyfile.acme"
assert_admin_off "$ROOT/packaging/debian/Caddyfile.http-only"
assert_public_url_map "$ROOT/packaging/debian/Caddyfile.acme"
assert_public_url_map "$ROOT/packaging/debian/Caddyfile.http-only"

echo "packaged Caddy listeners are loopback-only and admin API is off"
