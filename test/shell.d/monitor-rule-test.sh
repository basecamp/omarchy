#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
monitor_lua="$home_dir/.config/hypr/monitors.lua"

mkdir -p "$stub_bin" "$home_dir/.config/hypr"

# eDP-1 reports a description and sits at 0,960 scaled 2. DP-1 reports a
# description with a serial on the end, which is what makes abbreviated rules
# in a hand-written config the interesting case.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "monitors" && $2 == "all" && $3 == "-j" ]]; then
  printf '[{"name":"eDP-1","description":"BOE Panel","x":0,"y":960,"scale":2.00000,"transform":%s},{"name":"DP-1","description":"Acme Wide 42 SN123","x":1440,"y":0,"scale":1,"transform":0},{"name":"HDMI-A-1","description":"","x":4000,"y":0,"scale":1,"transform":0}]' \
    "${OMARCHY_TEST_TRANSFORM:-0}"
else
  exit 1
fi
SH
chmod +x "$stub_bin"/*

run_rule() {
  HOME="$home_dir" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-hyprland-monitor-rule" "$@"
}

# A config shaped like one a user actually keeps: a stock catch-all, rules in
# both identifier styles, comments, and commented-out examples.
write_config() {
  cat >"$monitor_lua" <<'LUA'
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", "2")
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Laptop left of the desk display, bottom edges aligned.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x480", scale = 2 })
hl.monitor({ output = "desc:Acme Wide", mode = "preferred", position = "1440x0", scale = 2 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })
LUA
}

rules_for() {
  grep -c "output = \"$1\"" "$monitor_lua"
}

# --- a rule keyed by connector name is rewritten in place ---

write_config
run_rule eDP-1
[[ $(rules_for "eDP-1") == "1" ]] || fail "the display keeps exactly one rule"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x960", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "the rule carries the display's current geometry"
pass "a rule keyed by connector name is rewritten in place"

# --- an abbreviated description still matches its display ---

# Hyprland matches desc: by prefix, so a rule saying "desc:Acme Wide" configures
# a display reporting "Acme Wide 42 SN123". Comparing identifiers exactly would
# miss it and append a second rule for a display that already has one.
write_config
run_rule DP-1
[[ $(grep -c 'output = "desc:Acme Wide"' "$monitor_lua") == "1" ]] ||
  fail "an abbreviated description is matched rather than duplicated"
grep -Fx 'hl.monitor({ output = "desc:Acme Wide", mode = "preferred", position = "1440x0", scale = 1 })' "$monitor_lua" >/dev/null ||
  fail "the abbreviated rule keeps its identifier and takes the new geometry"
pass "an abbreviated description is matched rather than duplicated"

# --- a display with no rule of its own gets one ---

write_config
before=$(grep -c 'hl.monitor' "$monitor_lua")
run_rule HDMI-A-1
[[ $(grep -c 'hl.monitor' "$monitor_lua") == $((before + 1)) ]] ||
  fail "a display with no rule gains exactly one"
grep -Fx 'hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "4000x0", scale = 1 })' "$monitor_lua" >/dev/null ||
  fail "a display without a description falls back to its connector name"
pass "a display with no rule of its own gains one"

# --- the rest of the file is left alone ---

write_config
cp "$monitor_lua" "$test_tmp/before.lua"
run_rule eDP-1
diff <(grep -v 'output = "eDP-1"' "$test_tmp/before.lua") <(grep -v 'output = "eDP-1"' "$monitor_lua") >/dev/null ||
  fail "every other line survives untouched"
grep -F -e '-- Laptop left of the desk display, bottom edges aligned.' "$monitor_lua" >/dev/null ||
  fail "comments survive"
grep -F -e '-- hl.monitor({ output = "DP-2"' "$monitor_lua" >/dev/null ||
  fail "commented-out examples are not mistaken for rules"
grep -F 'scale = omarchy_monitor_scale' "$monitor_lua" >/dev/null ||
  fail "the catch-all is left alone"
pass "everything else in the file survives untouched"

# --- rotation ---

write_config
OMARCHY_TEST_TRANSFORM=1 run_rule eDP-1
grep -F 'transform = 1' "$monitor_lua" >/dev/null || fail "a rotated display records its rotation"
pass "a rotated display records its rotation"

write_config
run_rule eDP-1
! grep -F 'transform' "$monitor_lua" >/dev/null || fail "an upright display records no rotation"
pass "an upright display records no rotation"

# --- refusals ---

write_config
run_rule DP-9 2>/dev/null && fail "an unknown display exits non-zero"
run_rule 2>/dev/null && fail "a missing display name exits non-zero"
diff "$test_tmp/before.lua" "$monitor_lua" >/dev/null || fail "a refused write leaves the file alone"
pass "an unknown or missing display is refused without touching the file"

# --- any single-line shape is recognised, and anything else is refused ---

# A Lua config can be written many ways: no spaces, indented, or using Lua's
# call-without-parentheses form. Matching the formatting Omarchy happens to ship
# would append a second rule for a display that already has one.
for shape in \
  'hl.monitor({output="DP-1", scale=1})' \
  '  hl.monitor({ output = "DP-1", scale = 1 })' \
  'hl.monitor { output = "DP-1", scale = 1 }'; do
  printf '%s\n' "$shape" >"$monitor_lua"
  run_rule DP-1
  [[ $(grep -c 'hl.monitor' "$monitor_lua") == "1" ]] ||
    fail "a rule written as: $shape is rewritten rather than duplicated"
done
pass "any single-line shape is rewritten rather than duplicated"

# Declining beats guessing: rewriting the wrong rule, or adding a second one,
# means whichever Hyprland loads last wins and silently drops the other.
printf 'local name = "DP-1"\nhl.monitor({ output = name, scale = 1 })\n' >"$monitor_lua"
cp "$monitor_lua" "$test_tmp/variable.lua"
run_rule DP-1 2>/dev/null && fail "a display named by a variable is refused"
diff "$test_tmp/variable.lua" "$monitor_lua" >/dev/null || fail "a refused file is left untouched"
pass "a display named by something other than a literal is refused"

printf 'hl.monitor({ output = "DP-1", scale = 1 })\nhl.monitor({ output = "desc:Acme Wide", scale = 2 })\n' >"$monitor_lua"
cp "$monitor_lua" "$test_tmp/two.lua"
run_rule DP-1 2>/dev/null && fail "a display with two rules already is refused"
diff "$test_tmp/two.lua" "$monitor_lua" >/dev/null || fail "a refused file is left untouched"
pass "a display that already has two rules is refused"

printf -- '-- hl.monitor({ output = "DP-1", scale = 1 })\n' >"$monitor_lua"
run_rule DP-1
[[ $(grep -c '^hl.monitor' "$monitor_lua") == "1" ]] ||
  fail "a commented-out rule does not stand in for a real one"
pass "a commented-out rule does not stand in for a real one"
