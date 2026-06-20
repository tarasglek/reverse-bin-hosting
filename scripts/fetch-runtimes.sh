#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/packaging/runtime-versions.env"

OS=linux
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) GOARCH=amd64; GNU_ARCH=x86_64 ;;
  aarch64|arm64) GOARCH=arm64; GNU_ARCH=aarch64 ;;
  *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

CACHE_DIR=${RUNTIME_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/reverse-bin-hosting/runtimes}
BUILD_DIR="$ROOT/build"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/reverse-bin-runtimes.XXXXXX")
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

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

install_cached() {
  src=$1
  name=$2
  install -m 0755 "$src" "$BUILD_DIR/$name"
}

# uv
UV_TAG="${UV_VERSION#v}"
UV_KEY="uv/${UV_TAG}/${OS}-${GOARCH}"
UV_BIN="$CACHE_DIR/$UV_KEY/uv"
if [ ! -x "$UV_BIN" ]; then
  UV_TAR="$CACHE_DIR/$UV_KEY/uv.tar.gz"
  fetch "https://github.com/astral-sh/uv/releases/download/${UV_TAG}/uv-${GNU_ARCH}-unknown-linux-gnu.tar.gz" "$UV_TAR"
  rm -rf "$TMP_DIR/uv"
  mkdir -p "$TMP_DIR/uv"
  tar -xzf "$UV_TAR" -C "$TMP_DIR/uv"
  install -m 0755 "$TMP_DIR/uv/uv-${GNU_ARCH}-unknown-linux-gnu/uv" "$UV_BIN"
fi
install_cached "$UV_BIN" uv

# landrun: build once into cache from tagged module source.
LANDRUN_KEY="landrun/${LANDRUN_VERSION}/${OS}-${GOARCH}"
LANDRUN_BIN="$CACHE_DIR/$LANDRUN_KEY/landrun"
if [ ! -x "$LANDRUN_BIN" ]; then
  mkdir -p "$(dirname -- "$LANDRUN_BIN")"
  GOBIN="$TMP_DIR/bin" GOOS=linux GOARCH="$GOARCH" go install "github.com/zouuup/landrun/cmd/landrun@${LANDRUN_VERSION}"
  install -m 0755 "$TMP_DIR/bin/landrun" "$LANDRUN_BIN"
fi
install_cached "$LANDRUN_BIN" landrun

# deno
DENO_KEY="deno/${DENO_VERSION}/${OS}-${GOARCH}"
DENO_BIN="$CACHE_DIR/$DENO_KEY/deno"
if [ ! -x "$DENO_BIN" ]; then
  DENO_ZIP="$CACHE_DIR/$DENO_KEY/deno.zip"
  fetch "https://github.com/denoland/deno/releases/download/${DENO_VERSION}/deno-${GNU_ARCH}-unknown-linux-gnu.zip" "$DENO_ZIP"
  rm -rf "$TMP_DIR/deno"
  mkdir -p "$TMP_DIR/deno"
  ( cd "$TMP_DIR/deno" && unzip -q "$DENO_ZIP" deno )
  install -m 0755 "$TMP_DIR/deno/deno" "$DENO_BIN"
fi
install_cached "$DENO_BIN" deno

# sops
SOPS_KEY="sops/${SOPS_VERSION}/${OS}-${GOARCH}"
SOPS_BIN="$CACHE_DIR/$SOPS_KEY/sops"
if [ ! -x "$SOPS_BIN" ]; then
  fetch "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${GOARCH}" "$SOPS_BIN"
  chmod 0755 "$SOPS_BIN"
fi
install_cached "$SOPS_BIN" sops

# age and age-keygen
AGE_KEY="age/${AGE_VERSION}/${OS}-${GOARCH}"
AGE_BIN="$CACHE_DIR/$AGE_KEY/age"
AGE_KEYGEN_BIN="$CACHE_DIR/$AGE_KEY/age-keygen"
if [ ! -x "$AGE_BIN" ] || [ ! -x "$AGE_KEYGEN_BIN" ]; then
  AGE_TAR="$CACHE_DIR/$AGE_KEY/age.tar.gz"
  fetch "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-${GOARCH}.tar.gz" "$AGE_TAR"
  rm -rf "$TMP_DIR/age"
  mkdir -p "$TMP_DIR/age"
  tar -xzf "$AGE_TAR" -C "$TMP_DIR/age"
  install -m 0755 "$TMP_DIR/age/age/age" "$AGE_BIN"
  install -m 0755 "$TMP_DIR/age/age/age-keygen" "$AGE_KEYGEN_BIN"
fi
install_cached "$AGE_BIN" age
install_cached "$AGE_KEYGEN_BIN" age-keygen

"$ROOT/scripts/check-runtime-versions.sh" "$BUILD_DIR"
