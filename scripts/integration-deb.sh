#!/bin/sh
set -eu

PACKAGE=${1:-}
PORT=${REVERSE_BIN_TEST_PORT:-17777}
STATIC_MARKER=reverse-bin-static-integration-ok
EXEC_MARKER=reverse-bin-executable-integration-ok

if [ "$(id -u)" -ne 0 ]; then
    echo "error: integration-deb.sh must run as root" >&2
    exit 1
fi
if [ -z "$PACKAGE" ] || [ ! -f "$PACKAGE" ]; then
    echo "error: pass the built reverse-bin .deb" >&2
    exit 1
fi

failure_logs() {
    status=$?
    if [ "$status" -ne 0 ]; then
        systemctl status reverse-bin.service --no-pager >&2 || true
        journalctl -u reverse-bin.service --no-pager -n 200 >&2 || true
    fi
    exit "$status"
}
trap failure_logs EXIT INT TERM

apt-get install -y "$PACKAGE"

cat > /etc/default/reverse-bin <<EOF
DOMAIN_SUFFIX=example.test
REVERSE_BIN_CADDYFILE=/etc/reverse-bin/Caddyfile.http-only
REVERSE_BIN_HTTP_PORT=$PORT
REVERSE_BIN_IDLE_TIMEOUT_MS=300000
REVERSE_BIN_HEALTH_TIMEOUT_MS=15000
REVERSE_BIN_TERMINATION_GRACE_MS=5000
REVERSE_BIN_TERMINATION_KILL_WAIT_MS=1000
EOF

install -d -o reverse-bin -g reverse-bin /var/lib/reverse-bin/apps/www/data
printf '%s\n' "$STATIC_MARKER" > /var/lib/reverse-bin/apps/www/index.html
chown reverse-bin:reverse-bin /var/lib/reverse-bin/apps/www/index.html

install -d -o reverse-bin -g reverse-bin /var/lib/reverse-bin/apps/exec/data
cat > /var/lib/reverse-bin/apps/exec/main.py <<'PY'
#!/usr/bin/python3
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

MARKER = "reverse-bin-executable-integration-ok"

class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        body = (MARKER + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass

HTTPServer(
    (os.environ["REVERSE_BIN_HOST"], int(os.environ["REVERSE_BIN_PORT"])),
    Handler,
).serve_forever()
PY
chown reverse-bin:reverse-bin /var/lib/reverse-bin/apps/exec/main.py
chmod 0755 /var/lib/reverse-bin/apps/exec/main.py

systemctl restart reverse-bin.service
systemctl is-active --quiet reverse-bin.service

request() {
    host=$1
    curl --fail --silent --show-error \
        --retry 30 --retry-delay 1 --retry-all-errors \
        --header "Host: $host" "http://127.0.0.1:$PORT/"
}

static_body=$(request example.test)
[ "$static_body" = "$STATIC_MARKER" ] || {
    echo "error: static route returned unexpected body: $static_body" >&2
    exit 1
}

socket_count=$(find /run/reverse-bin/static-apps -type s -name reverse-bin.sock 2>/dev/null | wc -l)
[ "$socket_count" -ge 1 ] || {
    echo "error: static route did not create its managed Unix socket" >&2
    exit 1
}

exec_body=$(request exec.example.test)
[ "$exec_body" = "$EXEC_MARKER" ] || {
    echo "error: executable route returned unexpected body: $exec_body" >&2
    exit 1
}

/usr/bin/reverse-bin-caddy list-modules | grep -Fxq http.handlers.reverse-bin
/usr/lib/reverse-bin/reverse-bin-detector --version | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+'
systemctl is-active --quiet reverse-bin.service

echo "Debian package integration test passed"
trap - EXIT INT TERM
