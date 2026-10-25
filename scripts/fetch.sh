# shellcheck shell=sh
# Sourced by the fetch-*runtimes.sh scripts.
#
# fetch URL OUT downloads URL to OUT unless OUT exists. A GitHub release
# asset must match the sha256 digest GitHub records for it, so a corrupted
# or swapped download fails the build. Other URLs (source archives) have no
# recorded digest.
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
  case $url in
    https://github.com/*/releases/download/*)
      digest=$(release_digest "$url") || { rm -f "$tmp"; return 1; }
      echo "$digest  $tmp" | sha256sum -c --quiet - || {
        rm -f "$tmp"
        echo "error: $url does not match GitHub's sha256 $digest" >&2
        return 1
      }
      ;;
  esac
  mv "$tmp" "$out"
}

# release_digest URL prints the sha256 GitHub records for a release asset URL.
release_digest() {
  path=${1#https://github.com/}
  repo=${path%%/releases/download/*}
  rest=${path#*/releases/download/}
  curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "https://api.github.com/repos/$repo/releases/tags/${rest%/*}" |
    python3 -c '
import json, sys
name = sys.argv[1]
for asset in json.load(sys.stdin)["assets"]:
    if asset["name"] == name and (asset.get("digest") or "").startswith("sha256:"):
        print(asset["digest"][len("sha256:"):])
        sys.exit(0)
sys.exit(f"error: no sha256 digest for release asset {name}")
' "${rest##*/}"
}
