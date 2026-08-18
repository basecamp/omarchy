#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/home" "$TMPDIR/bin"
CALLS="$TMPDIR/calls"

cat >"$TMPDIR/bin/fc-list" <<'SH'
#!/bin/bash
printf '%s\n' "CaskaydiaMono Nerd Font"
SH

cat >"$TMPDIR/bin/pgrep" <<'SH'
#!/bin/bash
# Pretend Ghostty and Foot are running so font-set should notify.
[[ $1 == -x && ( $2 == ghostty || $2 == foot ) ]]
SH

for command in omarchy-notification-send omarchy-restart-shell omarchy-hook; do
  cat >"$TMPDIR/bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$FAKE_CALLS"
SH
done
chmod +x "$TMPDIR/bin/"*

HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" FAKE_CALLS="$CALLS" \
  omarchy-font-set "CaskaydiaMono Nerd Font"

grep -q 'You must restart Ghostty to see font change' "$CALLS" ||
  fail "font-set does not notify when Ghostty is running"
grep -q 'You must restart Foot to see font change' "$CALLS" ||
  fail "font-set does not notify when Foot is running"
if grep -q -- '-g You must restart Ghostty' "$CALLS" ||
  grep -q -- '-g You must restart Foot' "$CALLS"; then
  fail "font-set passes the restart message as a glyph"
fi
pass "font-set notifies a restart without consuming the message as a glyph"
