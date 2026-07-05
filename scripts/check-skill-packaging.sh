#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SKILL="$ROOT/skills/reverse-bin-web-apps/SKILL.md"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "repo-local reverse-bin web app skill missing"
grep -q '^name: reverse-bin-web-apps$' "$SKILL" || fail "skill name mismatch"
grep -q 'Use when writing or debugging web apps' "$SKILL" || fail "skill description trigger missing"

grep -q 'skills/reverse-bin-web-apps/SKILL.md usr/share/reverse-bin/skills/reverse-bin-web-apps/' "$ROOT/debian/install" || fail "debian/install must package reverse-bin app skill"
grep -q '/var/lib/reverse-bin/apps/skills/reverse-bin-web-apps' "$ROOT/debian/postinst" || fail "postinst must seed skill into APP_ROOT skills dir"
grep -q '/usr/share/reverse-bin/skills/reverse-bin-web-apps/SKILL.md' "$ROOT/debian/postinst" || fail "postinst must copy packaged skill"
grep -q 'reverse-bin app skill: /var/lib/reverse-bin/apps/skills/reverse-bin-web-apps/SKILL.md' "$ROOT/debian/reverse-bin.service" || fail "systemd service must log skill path"

echo "skill packaging checks passed"
