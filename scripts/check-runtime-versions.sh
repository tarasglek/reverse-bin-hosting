#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/packaging/runtime-versions.env"

BIN_DIR=${1:-$ROOT/build}
fail=0

need_file() {
  name=$1
  if [ ! -x "$BIN_DIR/$name" ]; then
    echo "missing executable: $BIN_DIR/$name" >&2
    fail=1
    return 1
  fi
}

check_eq() {
  name=$1
  got=$2
  want=$3
  if [ "$got" != "$want" ]; then
    echo "$name version mismatch: got $got, want $want" >&2
    fail=1
  fi
}

go_module_version() {
  bin=$1
  module=$2
  go version -m "$bin" 2>/dev/null | awk -v module="$module" '$1 == "mod" && $2 == module { print $3 }'
}

for name in uv landrun reverse-bin-detector deno sops age age-keygen; do
  need_file "$name" || true
done

if [ "$fail" -eq 0 ]; then
  uv_ver=$("$BIN_DIR/uv" --version | awk '{print $2}')
  landrun_ver=$(go_module_version "$BIN_DIR/landrun" github.com/zouuup/landrun)
  detector_ver=$(go_module_version "$BIN_DIR/reverse-bin-detector" github.com/tarasglek/reverse-bin-detector)
  deno_ver=$("$BIN_DIR/deno" --version | awk 'NR==1 {print $2}')
  sops_ver=$("$BIN_DIR/sops" --version 2>/dev/null | awk 'NR==1 {print $2}')
  age_ver=$("$BIN_DIR/age" --version | awk '{print $1}')
  age_keygen_ver=$("$BIN_DIR/age-keygen" --version | awk '{print $1}')

  check_eq uv "$uv_ver" "${UV_VERSION#v}"
  check_eq landrun "$landrun_ver" "$LANDRUN_VERSION"
  check_eq reverse-bin-detector "$detector_ver" "$REVERSE_BIN_DETECTOR_VERSION"
  check_eq deno "v$deno_ver" "$DENO_VERSION"
  check_eq sops "v$sops_ver" "$SOPS_VERSION"
  check_eq age "$age_ver" "$AGE_VERSION"
  check_eq age-keygen "$age_keygen_ver" "$AGE_VERSION"
fi

if [ "$fail" -ne 0 ]; then
  echo "runtime version check failed for $BIN_DIR" >&2
  exit 1
fi

echo "runtime versions match packaging/runtime-versions.env"
