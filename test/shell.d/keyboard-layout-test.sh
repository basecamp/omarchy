#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
export CALLS="$tmp_dir/calls"
: >"$CALLS"

# The power button and other keymap-less inputs also sit in `keyboards`, so the
# fixture keeps a non-main entry first: the command must answer with the main
# keyboard, not whichever happens to lead the list. The main keymap carries a
# space and parentheses on purpose — xkb names them like that, and they must
# survive the trip to the OSD intact.
cat >"$tmp_dir/bin/hyprctl" <<'STUB'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALLS"
if [[ $1 == "-j" && $2 == "devices" ]]; then
  cat <<'JSON'
{
  "keyboards": [
    { "name": "power-button", "main": false, "active_keymap": "English (US)" },
    { "name": "real-keyboard", "main": true, "active_keymap": "Portuguese (Brazil)" }
  ]
}
JSON
fi
exit 0
STUB

cat >"$tmp_dir/bin/omarchy-osd" <<'STUB'
#!/bin/bash
printf 'omarchy-osd %s\n' "$*" >>"$CALLS"
STUB

chmod +x "$tmp_dir/bin/hyprctl" "$tmp_dir/bin/omarchy-osd"

run() {
  : >"$CALLS"
  PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-hyprland-keyboard-layout" "$@"
}

run
grep -Fx 'hyprctl switchxkblayout all next' "$CALLS" >/dev/null || fail "default action dispatches switchxkblayout all next"
grep -Fx 'omarchy-osd -i keyboard -m Portuguese (Brazil)' "$CALLS" >/dev/null || fail "switch shows the main keyboard layout on the OSD"
pass "switch dispatches and shows the main keyboard layout on the OSD"

run prev
grep -Fx 'hyprctl switchxkblayout all prev' "$CALLS" >/dev/null || fail "prev dispatches switchxkblayout all prev"
pass "prev dispatches switchxkblayout all prev"

status_output=$(run status)
[[ $status_output == "Portuguese (Brazil)" ]] || fail "status prints the main keyboard layout" "$status_output"
if grep -q 'switchxkblayout' "$CALLS"; then
  fail "status does not switch the layout"
fi
if grep -q 'omarchy-osd' "$CALLS"; then
  fail "status does not open the OSD"
fi
pass "status reports without switching or opening the OSD"

if run bogus 2>/dev/null; then
  fail "unknown action exits non-zero"
fi
pass "unknown action exits non-zero"
