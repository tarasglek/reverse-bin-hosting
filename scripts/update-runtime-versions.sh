#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/packaging/runtime-versions.env"
TMP=$(mktemp "${TMPDIR:-/tmp}/runtime-versions.XXXXXX")
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT INT TERM

latest_github_tag() {
  repo=$1
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
}

caddy_plugin_version=$(go list -m -json github.com/tarasglek/caddy-reverse-bin@latest \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["Version"])')
uv_version=$(latest_github_tag astral-sh/uv)
landrun_version=$(latest_github_tag zouuup/landrun)
deno_version=$(latest_github_tag denoland/deno)
sops_version=$(latest_github_tag getsops/sops)
age_version=$(latest_github_tag FiloSottile/age)

cat > "$TMP" <<EOF
CADDY_REVERSE_BIN_PLUGIN=github.com/tarasglek/caddy-reverse-bin@${caddy_plugin_version}
UV_VERSION=${uv_version#v}
LANDRUN_VERSION=${landrun_version}
DENO_VERSION=${deno_version}
SOPS_VERSION=${sops_version}
AGE_VERSION=${age_version}
EOF

mv "$TMP" "$OUT"
trap - EXIT INT TERM

echo "updated $OUT"
cat "$OUT"
