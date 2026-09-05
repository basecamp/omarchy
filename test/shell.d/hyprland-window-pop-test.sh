#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
dispatch_log="$test_dir/dispatch.log"
query_log="$test_dir/query.log"
stderr_log="$test_dir/stderr.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "activewindow" && $2 == "-j" ]]; then
  printf '%s\n' "$OMARCHY_TEST_ACTIVE_JSON"
elif [[ $1 == "monitors" && $2 == "-j" ]]; then
  printf 'monitors\n' >>"$OMARCHY_TEST_QUERY_LOG"
  (( OMARCHY_TEST_MONITORS_STATUS == 0 )) || exit "$OMARCHY_TEST_MONITORS_STATUS"
  printf '%s\n' "$OMARCHY_TEST_MONITORS_JSON"
elif [[ $1 == "dispatch" ]]; then
  shift
  command=$1
  printf '%s' "$command" >>"$OMARCHY_TEST_DISPATCH_LOG"
  shift
  if (( $# > 0 )); then
    printf '\t%s' "$@" >>"$OMARCHY_TEST_DISPATCH_LOG"
  fi
  printf '\n' >>"$OMARCHY_TEST_DISPATCH_LOG"

  if [[ $command == hl.dsp.* ]]; then
    exit "$OMARCHY_TEST_LUA_STATUS"
  fi
else
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"

active_json='{"address":"0xabc","monitor":7,"pinned":false}'
monitors_json='[{"id":7,"width":2560,"height":1440,"scale":1,"transform":0,"reserved":[0,0,0,0]}]'

run_pop() {
  : >"$dispatch_log"
  : >"$query_log"
  : >"$stderr_log"

  OMARCHY_TEST_ACTIVE_JSON="${OMARCHY_TEST_ACTIVE_JSON:-$active_json}" \
    OMARCHY_TEST_MONITORS_JSON="${OMARCHY_TEST_MONITORS_JSON:-$monitors_json}" \
    OMARCHY_TEST_MONITORS_STATUS="${OMARCHY_TEST_MONITORS_STATUS:-0}" \
    OMARCHY_TEST_LUA_STATUS="${OMARCHY_TEST_LUA_STATUS:-0}" \
    OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
    OMARCHY_TEST_QUERY_LOG="$query_log" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-hyprland-window-pop" "$@" 2>"$stderr_log"
}

assert_lua_resize() {
  local width=$1
  local height=$2
  grep -Fx "hl.dsp.window.resize({ window = \"address:0xabc\", x = $width, y = $height })" "$dispatch_log" >/dev/null ||
    fail "resize uses ${width}x${height}" "$(<"$dispatch_log")"
}

assert_legacy_resize() {
  local width=$1
  local height=$2
  grep -Fx $'resizeactive\texact\t'"$width"$'\t'"$height"$'\taddress:0xabc' "$dispatch_log" >/dev/null ||
    fail "legacy resize uses ${width}x${height}" "$(<"$dispatch_log")"
}

run_pop
assert_lua_resize 1300 900
pass "large 1x monitors keep the 1300x900 defaults"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1920,"height":1080,"scale":1.6,"transform":0}]' run_pop
assert_lua_resize 1080 607
pass "fractional scaling sizes against the logical workspace"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1200,"height":800,"scale":1,"transform":0,"reserved":[10,20,30,40]}]' run_pop
assert_lua_resize 1044 666
pass "reserved work-area edges are excluded"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1920,"height":1080,"scale":1,"transform":1}]' run_pop
assert_lua_resize 972 900
OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1920,"height":1080,"scale":1,"transform":3}]' run_pop
assert_lua_resize 972 900
pass "90 and 270 degree transforms swap monitor dimensions"

OMARCHY_TEST_ACTIVE_JSON='{"address":"0xabc","monitor":9,"pinned":false}' \
  OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":3840,"height":2160,"scale":1},{"id":9,"width":1000,"height":700,"scale":1}]' \
  run_pop
assert_lua_resize 900 630
pass "the active window monitor id selects the target monitor"

run_pop 777 555
assert_lua_resize 777 555
[[ ! -s $query_log ]] || fail "explicit dimensions do not query monitors"
pass "explicit width and height stay unchanged"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1000,"height":700,"scale":1}]' run_pop 777
assert_lua_resize 777 630
pass "an explicit width keeps a dynamic height"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1000,"height":700,"scale":1}]' run_pop '' 555
assert_lua_resize 900 555
pass "an empty width keeps an explicit height"

assert_fallback() {
  assert_lua_resize 1300 900
  [[ ! -s $stderr_log ]] || fail "$1 is silent" "$(<"$stderr_log")"
  pass "$1 falls back silently"
}

OMARCHY_TEST_MONITORS_STATUS=1 run_pop
assert_fallback "a failed monitor query"

OMARCHY_TEST_MONITORS_JSON='[{"id":8,"width":1000,"height":700,"scale":1}]' run_pop
assert_fallback "a missing monitor id"

OMARCHY_TEST_MONITORS_JSON='not-json' run_pop
assert_fallback "invalid monitor JSON"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1000,"height":700,"scale":0}]' run_pop
assert_fallback "a zero monitor scale"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1000,"height":700}]' run_pop
assert_fallback "a missing monitor scale"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":0,"height":700,"scale":1}]' run_pop
assert_fallback "an invalid monitor size"

OMARCHY_TEST_ACTIVE_JSON='{"address":"0xabc","monitor":7,"pinned":true}' \
  OMARCHY_TEST_MONITORS_STATUS=1 run_pop
[[ ! -s $query_log ]] || fail "pinned windows do not query monitors"
! grep -F 'resize' "$dispatch_log" >/dev/null || fail "pinned windows are not resized" "$(<"$dispatch_log")"
grep -F 'window.pin' "$dispatch_log" >/dev/null || fail "pinned windows still unpin"
pass "pinned windows only follow the unpin flow"

OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1000,"height":700,"scale":1}]' run_pop
assert_lua_resize 900 630
! grep -F 'resizeactive' "$dispatch_log" >/dev/null || fail "successful Lua dispatch does not use the legacy resize"
pass "successful Lua dispatch uses the dynamic size"

OMARCHY_TEST_LUA_STATUS=1 \
  OMARCHY_TEST_MONITORS_JSON='[{"id":7,"width":1000,"height":700,"scale":1}]' run_pop
assert_lua_resize 900 630
assert_legacy_resize 900 630
pass "legacy fallback reuses the dynamic size"

run_pop 777 555 42 84
grep -Fx 'hl.dsp.window.move({ window = "address:0xabc", x = 42, y = 84 })' "$dispatch_log" >/dev/null ||
  fail "custom coordinates keep the Lua move" "$(<"$dispatch_log")"
! grep -F 'window.center' "$dispatch_log" >/dev/null || fail "custom coordinates do not center the window"
pass "custom x and y preserve the existing move behavior"
