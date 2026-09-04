#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/home/.config/omarchy/themes/my-cool-theme" "$TMPDIR/bin"
printf 'ok\n' >"$TMPDIR/home/.config/omarchy/themes/my-cool-theme/marker"

cat >"$TMPDIR/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$TMPDIR/bin/omarchy-notification-send"

HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  omarchy-theme-remove "My Cool Theme" ||
  fail "theme remove does not accept the display name theme set already normalises"
[[ ! -e $TMPDIR/home/.config/omarchy/themes/my-cool-theme ]] ||
  fail "theme remove left the display-name theme on disk"
pass "theme remove accepts a quoted display name"

mkdir -p "$TMPDIR/home/.config/omarchy/themes/already-slug"
HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  omarchy-theme-remove already-slug
[[ ! -e $TMPDIR/home/.config/omarchy/themes/already-slug ]] ||
  fail "theme remove rejects a directory slug"
pass "theme remove still accepts a directory slug"
