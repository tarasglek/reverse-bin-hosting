#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$APP_DIR/.env"
PASSWORD_FILE="$APP_DIR/.logs-dashboard-password"
DEFAULTS_FILE=${DEFAULTS_FILE:-/etc/default/reverse-bin}

cd "$APP_DIR"
mkdir -p data/html caddy-logs
touch caddy-logs/access.log
if [ ! -s data/html/index.html ]; then
  printf '%s\n' 'GoAccess dashboard initializing. Reload shortly.' > data/html/index.html
fi

if [ -z "${DOMAIN_SUFFIX:-}" ] && [ -f "$DEFAULTS_FILE" ]; then
  DOMAIN_SUFFIX=$(awk -F= '$1 == "DOMAIN_SUFFIX" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^"|"$/, "", $2); gsub(/^'"'"'|'"'"'$/, "", $2); print $2; exit }' "$DEFAULTS_FILE")
fi
if [ -z "${DOMAIN_SUFFIX:-}" ]; then
  echo "error: DOMAIN_SUFFIX is missing; set it in /etc/default/reverse-bin or environment" >&2
  exit 1
fi
LOGS_WS_URL=${LOGS_WS_URL:-logs.$DOMAIN_SUFFIX/ws}
LOGS_WS_PORT=${LOGS_WS_PORT:-443}

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
awk '!/^LOGS_BASIC_AUTH_HASH=/ && !/^LOGS_WS_URL=/ && !/^LOGS_WS_PORT=/' "$ENV_FILE" > "$tmp"
printf 'LOGS_BASIC_AUTH_HASH=%s\n' "$hash" >> "$tmp"
printf 'LOGS_WS_URL=%s\n' "$LOGS_WS_URL" >> "$tmp"
printf 'LOGS_WS_PORT=%s\n' "$LOGS_WS_PORT" >> "$tmp"
cat "$tmp" > "$ENV_FILE"
rm -f "$tmp"

cat <<EOF
Logging dashboard credentials ready.
URL: https://logs.$DOMAIN_SUFFIX/
user: admin
password: cat $PASSWORD_FILE
EOF
