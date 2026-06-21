#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/packaging/runtime-versions.env"

OS=linux
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) WEBSOCAT_ARCH=x86_64-unknown-linux-musl ;;
  aarch64|arm64) WEBSOCAT_ARCH=aarch64-unknown-linux-musl ;;
  *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

CACHE_DIR=${RUNTIME_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/reverse-bin-hosting/runtimes}
BUILD_DIR="$ROOT/build/test-tools"
mkdir -p "$BUILD_DIR" "$CACHE_DIR"

fetch() {
  url=$1
  out=$2
  if [ -s "$out" ]; then
    echo "cache hit $out" >&2
    return 0
  fi
  mkdir -p "$(dirname -- "$out")"
  tmp="$out.tmp.$$"
  echo "fetch $url" >&2
  curl -fsSL "$url" -o "$tmp"
  mv "$tmp" "$out"
}

WEBSOCAT_KEY="websocat/${WEBSOCAT_VERSION}/${OS}-${WEBSOCAT_ARCH}"
WEBSOCAT_BIN="$CACHE_DIR/$WEBSOCAT_KEY/websocat"
if [ ! -x "$WEBSOCAT_BIN" ]; then
  fetch "https://github.com/vi/websocat/releases/download/${WEBSOCAT_VERSION}/websocat.${WEBSOCAT_ARCH}" "$WEBSOCAT_BIN"
  chmod 0755 "$WEBSOCAT_BIN"
fi
install -m 0755 "$WEBSOCAT_BIN" "$BUILD_DIR/websocat"

"$BUILD_DIR/websocat" --version | grep "${WEBSOCAT_VERSION#v}"
