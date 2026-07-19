#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKFLOW="$ROOT/.github/workflows/package.yml"
UPDATER="$ROOT/scripts/update-runtime-versions.sh"
PROCESS="$ROOT/RELESE-PROCESS.md"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "package workflow missing"
[ -f "$UPDATER" ] || fail "runtime updater missing"
[ -f "$PROCESS" ] || fail "release process doc missing"

grep -q 'make update-runtime-versions' "$WORKFLOW" || fail "CI must run runtime version updater"
grep -q 'git diff --exit-code packaging/runtime-versions.env' "$WORKFLOW" || fail "CI must fail when runtime version updater changes lockfile"
grep -q 'websocat_version=' "$UPDATER" || fail "runtime updater must refresh WEBSOCAT_VERSION"
grep -q 'WEBSOCAT_VERSION=${websocat_version}' "$UPDATER" || fail "runtime updater must write WEBSOCAT_VERSION"
grep -q 'make update-runtime-versions' "$PROCESS" || fail "release process must document runtime update gate"
grep -q 'git diff --exit-code packaging/runtime-versions.env' "$PROCESS" || fail "release process must document lockfile diff gate"
grep -q 'generate_release_notes: true' "$WORKFLOW" || fail "tag releases must generate release notes"
grep -q 'Require release notes' "$WORKFLOW" || fail "tag releases must reject empty release notes"
grep -q 'gh release view' "$WORKFLOW" || fail "release notes guard must inspect the GitHub release"

echo "release gate checks passed"
