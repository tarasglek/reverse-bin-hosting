#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/packaging/runtime-versions.env"
TMP=$(mktemp "${TMPDIR:-/tmp}/runtime-versions.XXXXXX")
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT INT TERM

latest_github_release() {
  repo=$1
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
}

latest_github_tag() {
  repo=$1
  curl -fsSL "https://api.github.com/repos/$repo/tags" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["name"])'
}

caddy_plugin_version=$(latest_github_release tarasglek/caddy-reverse-bin)
uv_version=$(latest_github_release astral-sh/uv)
landrun_version=$(latest_github_release zouuup/landrun)
detector_version=$(latest_github_release tarasglek/reverse-bin-detector)
deno_version=$(latest_github_release denoland/deno)
sops_version=$(latest_github_release getsops/sops)
age_version=$(latest_github_release FiloSottile/age)
goaccess_version=$(latest_github_tag allinurl/goaccess)
websocat_version=$(latest_github_tag vi/websocat)

cat > "$TMP" <<EOF
CADDY_REVERSE_BIN_PLUGIN=github.com/tarasglek/caddy-reverse-bin@${caddy_plugin_version}
REVERSE_BIN_DETECTOR_VERSION=${detector_version}
UV_VERSION=${uv_version#v}
LANDRUN_VERSION=${landrun_version}
DENO_VERSION=${deno_version}
SOPS_VERSION=${sops_version}
AGE_VERSION=${age_version}
GOACCESS_VERSION=${goaccess_version}
WEBSOCAT_VERSION=${websocat_version}
EOF

mv "$TMP" "$OUT"
trap - EXIT INT TERM

echo "updated $OUT"
cat "$OUT"
