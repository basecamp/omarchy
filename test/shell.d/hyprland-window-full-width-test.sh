#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/hyprctl" <<'BASH'
#!/bin/bash

case "$1 $2" in
  "activewindow -j") printf '%s\n' "$HYPR_ACTIVE_WINDOW"; exit 0 ;;
  "workspaces -j") printf '%s\n' "$HYPR_WORKSPACES"; exit 0 ;;
esac

if [[ $1 == "getoption" && $2 == "scrolling:column_width" ]]; then
  printf '{"float":%s}\n' "$HYPR_COLUMN_WIDTH"
  exit 0
fi

if [[ $1 == "dispatch" ]]; then
  printf '%s\n' "$2" >>"$HYPRCTL_LOG"
  exit 0
fi

exit 1
BASH
chmod +x "$tmpdir/hyprctl"

log="$tmpdir/hyprctl.log"

# Run the toggle against stubbed compositor state and return what it dispatched,
# newline-separated, so a case asserts on the whole sequence.
toggle() {
  local window="$1" workspaces="$2" column_width="${3:-0.49}"

  : >"$log"
  PATH="$tmpdir:$PATH" HYPRCTL_LOG="$log" \
    HYPR_ACTIVE_WINDOW="$window" \
    HYPR_WORKSPACES="$workspaces" \
    HYPR_COLUMN_WIDTH="$column_width" \
    "$ROOT/bin/omarchy-hyprland-window-full-width-toggle"
  cat "$log"
}

assert_dispatches() {
  local description="$1" expected="$2" actual="$3"

  [[ $actual == "$expected" ]] || fail "$description" "expected:
$expected
got:
$actual"
  pass "$description"
}

scrolling='[{"id":1,"name":"1","tiledLayout":"scrolling"}]'
dwindle='[{"id":1,"name":"1","tiledLayout":"dwindle"}]'
special='[{"id":1,"name":"1","tiledLayout":"dwindle"},{"id":-99,"name":"special:scratchpad","tiledLayout":"scrolling"}]'

window() {
  local tags="${1:-[]}" workspace="${2:-1}" floating="${3:-false}" fullscreen="${4:-0}"

  printf '{"workspace":{"id":%s},"floating":%s,"fullscreen":%s,"tags":%s}' \
    "$workspace" "$floating" "$fullscreen" "$tags"
}

maximize='hl.dsp.window.fullscreen({ mode = "maximized" })'

assert_dispatches "an untagged column widens to full and takes the tag" \
  'hl.dsp.layout("colresize 1.0")
hl.dsp.window.tag({ tag = "+full-width" })' \
  "$(toggle "$(window '["default-opacity*"]')" "$scrolling")"

assert_dispatches "a tagged column returns to the configured width and drops the tag" \
  'hl.dsp.layout("colresize 0.49")
hl.dsp.window.tag({ tag = "-full-width" })' \
  "$(toggle "$(window '["full-width","default-opacity*"]')" "$scrolling")"

# The bug this replaced: a 0.97 column measures wider than any threshold below
# it, so a width test called it full on the first press and never widened it.
assert_dispatches "a near-full configured width still toggles" \
  'hl.dsp.layout("colresize 1.0")
hl.dsp.window.tag({ tag = "+full-width" })' \
  "$(toggle "$(window '[]')" "$scrolling" 0.97)"

assert_dispatches "a near-full configured width returns to it" \
  'hl.dsp.layout("colresize 0.97")
hl.dsp.window.tag({ tag = "-full-width" })' \
  "$(toggle "$(window '["full-width"]')" "$scrolling" 0.97)"

# Rule-assigned tags carry a trailing "*", so a tag named in a window rule must
# not read as the dynamic one this command sets.
assert_dispatches "a rule-assigned full-width tag reads as set" \
  'hl.dsp.layout("colresize 0.49")
hl.dsp.window.tag({ tag = "-full-width" })' \
  "$(toggle "$(window '["full-width*"]')" "$scrolling")"

assert_dispatches "a scrolling special workspace follows the focused window" \
  'hl.dsp.layout("colresize 1.0")
hl.dsp.window.tag({ tag = "+full-width" })' \
  "$(toggle "$(window '[]' -99)" "$special")"

assert_dispatches "a dwindle workspace keeps maximizing" \
  "$maximize" "$(toggle "$(window '[]')" "$dwindle")"

assert_dispatches "a floating window keeps maximizing" \
  "$maximize" "$(toggle "$(window '[]' 1 true)" "$scrolling")"

assert_dispatches "an already-fullscreen window keeps maximizing" \
  "$maximize" "$(toggle "$(window '[]' 1 false 2)" "$scrolling")"
