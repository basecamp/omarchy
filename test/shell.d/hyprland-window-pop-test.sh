#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "activewindow" && $2 == "-j" ]]; then
  printf '%s\n' "$HYPR_ACTIVE_WINDOW"
elif [[ $1 == "monitors" && $2 == "-j" ]]; then
  printf '%s\n' "$*" >>"$HYPRCTL_MONITORS_LOG"
  printf '%s\n' "$HYPR_MONITORS"
elif [[ $1 == "dispatch" ]]; then
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
else
  exit 1
fi
SH
chmod +x "$mock_bin/hyprctl"

run_pop() {
  local active_window="$1"
  local monitors="$2"
  shift 2

  PATH="$mock_bin:$PATH" \
    HYPR_ACTIVE_WINDOW="$active_window" \
    HYPR_MONITORS="$monitors" \
    HYPRCTL_LOG="$hyprctl_log" \
    HYPRCTL_MONITORS_LOG="$hyprctl_monitors_log" \
    "$ROOT/bin/omarchy-hyprland-window-pop" "$@"
}

assert_resize() {
  local expected="$1"

  grep -Fq "$expected" "$hyprctl_log" || fail "pop-out resizes to $expected" "$(<"$hyprctl_log")"
  pass "pop-out resizes to $expected"
}

hyprctl_log="$test_tmp/hyprctl.log"
hyprctl_monitors_log="$test_tmp/hyprctl-monitors.log"

run_pop \
  '{"address":"0xabc","pinned":false,"monitor":2}' \
  '[{"id":1,"width":1920,"height":1080,"scale":1,"transform":0,"reserved":[0,0,0,0]},{"id":2,"width":3840,"height":2160,"scale":2,"transform":0,"reserved":[0,30,0,40]}]'
assert_resize 'hl.dsp.window.resize({ window = "address:0xabc", x = 1536, y = 808 })'

>"$hyprctl_log"
>"$hyprctl_monitors_log"
run_pop \
  '{"address":"0xdef","pinned":false,"monitor":3}' \
  '[{"id":3,"width":2160,"height":3840,"scale":2,"transform":1,"reserved":[40,10,20,30]}]'
assert_resize 'hl.dsp.window.resize({ window = "address:0xdef", x = 1488, y = 832 })'

>"$hyprctl_log"
>"$hyprctl_monitors_log"
run_pop \
  '{"address":"0x123","pinned":false,"monitor":4}' \
  '[]' \
  1300 900 123 456
assert_resize 'hl.dsp.window.resize({ window = "address:0x123", x = 1300, y = 900 })'
grep -Fq 'dispatch hl.dsp.window.move({ window = "address:0x123", x = 123, y = 456 })' "$hyprctl_log" || fail "explicit position is preserved" "$(<"$hyprctl_log")"
pass "explicit position is preserved"
[[ ! -s $hyprctl_monitors_log ]] || fail "explicit dimensions do not query monitor geometry" "$(<"$hyprctl_monitors_log")"
pass "explicit dimensions do not query monitor geometry"
