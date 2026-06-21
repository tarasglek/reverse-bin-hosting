#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$APP_DIR/.env"
PASSWORD_FILE="$APP_DIR/.logs-dashboard-password"
PACKAGE_PASSWORD_FILE=/var/lib/reverse-bin/apps/logs/.logs-dashboard-password

cd "$APP_DIR"
mkdir -p data/html caddy-logs
touch caddy-logs/access.log
GOACCESS_BIN=${GOACCESS_BIN:-/usr/lib/reverse-bin/goaccess}
if [ ! -s data/html/index.html ] && [ -x "$GOACCESS_BIN" ]; then
  "$GOACCESS_BIN" caddy-logs/access.log --log-format=CADDY -o data/html/index.html >/dev/null 2>&1
fi

if [ ! -f "$PASSWORD_FILE" ]; then
  umask 077
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$PASSWORD_FILE"
  printf '\n' >> "$PASSWORD_FILE"
fi
chmod 600 "$PASSWORD_FILE"
if getent passwd reverse-bin >/dev/null 2>&1 && getent group reverse-bin >/dev/null 2>&1; then
  chown reverse-bin:reverse-bin "$PASSWORD_FILE" 2>/dev/null || true
fi

password=$(tr -d '\r\n' < "$PASSWORD_FILE")
hash=$(reverse-bin-caddy hash-password --plaintext "$password")

tmp=$(mktemp "$ENV_FILE.XXXXXX")
awk '!/^LOGS_BASIC_AUTH_HASH=/' "$ENV_FILE" > "$tmp"
printf 'LOGS_BASIC_AUTH_HASH=%s\n' "$hash" >> "$tmp"
cat "$tmp" > "$ENV_FILE"
rm -f "$tmp"

cat <<EOF
Logging dashboard credentials ready.
URL: https://logs.<your-domain>/
user: admin
password: cat $PACKAGE_PASSWORD_FILE
EOF
