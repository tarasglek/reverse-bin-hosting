#!/usr/bin/env sh
# Usage: vulncheck-binaries.sh BINARY...
# Fails when a binary in build/ links a vulnerable symbol that has a released
# fix, or cannot be scanned. Only binaries we build are passed: prebuilt
# upstream ones are held at their latest release, so a fix needs upstream.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GOVULNCHECK=${GOVULNCHECK:-go run golang.org/x/vuln/cmd/govulncheck@latest}
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT INT TERM

status=0
for bin in "$@"; do
  [ -x "$ROOT/build/$bin" ] || { echo "error: build/$bin missing; run make deb first" >&2; exit 1; }
  # shellcheck disable=SC2086 # GOVULNCHECK is a command line
  $GOVULNCHECK -mode=binary -format json "$ROOT/build/$bin" > "$OUT" \
    || { echo "error: govulncheck failed on $bin" >&2; exit 1; }
  found=$(jq -r 'select((.finding.fixed_version // "") != "" and .finding.trace[0].function != null)
      | .finding | "\(.osv) \(.trace[0].module)@\(.trace[0].version) -> \(.fixed_version)"' "$OUT" | sort -u)
  if [ -n "$found" ]; then
    echo "$found" | sed "s/^/$bin: /"
    echo "error: $bin has fixable vulnerabilities; bump its dependencies or Go toolchain" >&2
    status=1
  else
    echo "$bin: no fixable vulnerabilities"
  fi
done
exit "$status"
