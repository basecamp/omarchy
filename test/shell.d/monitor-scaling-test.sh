#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
eval_out="$test_tmp/hyprctl-eval"
home_dir="$test_tmp/home"
monitor_lua="$home_dir/.config/hypr/monitors.lua"
scale_log="$home_dir/.local/state/omarchy/monitor-scaling.log"

mkdir -p "$stub_bin" "$home_dir/.config/hypr"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" ]]; then
  primary=$(printf '{"name":"eDP-1","description":"BOE NE180WUM-NX1","focused":true,"scale":%s,"width":%s,"height":%s,"refreshRate":120.0}' \
    "${OMARCHY_TEST_MONITOR_SCALE:-2}" "${OMARCHY_TEST_MONITOR_WIDTH:-2880}" "${OMARCHY_TEST_MONITOR_HEIGHT:-1800}")
  if [[ -n ${OMARCHY_TEST_SECOND_MONITOR:-} ]]; then
    printf '[%s,{"name":"HDMI-A-1","description":"LG Electronics LG HDR 4K 0x0007F1E8","focused":false,"scale":1,"width":2560,"height":1440,"refreshRate":60.0}]' "$primary"
  else
    printf '[%s]' "$primary"
  fi
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >"$OMARCHY_TEST_HYPRCTL_EVAL_OUT"
else
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"

# The shape monitors.lua ships in: a catch-all rule reading the shared scale
# variable, and no rule naming any output.
write_monitor_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = 2
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
local omarchy_gdk_scale = 2
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
LUA
}

run_scaling() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_EVAL_OUT="$eval_out" \
    OMARCHY_TEST_MONITOR_SCALE="${OMARCHY_TEST_MONITOR_SCALE:-2}" \
    "$ROOT/bin/omarchy-hyprland-monitor-scaling" "$@"
}

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling up
grep -F 'scale = 3' "$eval_out" >/dev/null || fail "monitor scaling up reaches 3x"
grep -Fx 'local omarchy_monitor_scale = 3' "$monitor_lua" >/dev/null || fail "monitor scaling up persists 3x"
grep -F $'requested=up\tcurrent=2\tnew=3\tmonitor=eDP-1' "$scale_log" >/dev/null || fail "monitor scaling up writes audit log"
pass "monitor scaling up reaches 3x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=3 run_scaling down
grep -F 'scale = 2' "$eval_out" >/dev/null || fail "monitor scaling down recovers 3x to 2x"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null || fail "monitor scaling down persists 2x from 3x"
pass "monitor scaling down recovers 3x to 2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=3.0000000000000004 run_scaling down
grep -F 'scale = 2' "$eval_out" >/dev/null || fail "monitor scaling down snaps floating point 3x to 2x"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null || fail "monitor scaling down persists 2x from floating point 3x"
pass "monitor scaling down snaps floating point 3x to 2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 3
grep -F 'scale = 3' "$eval_out" >/dev/null || fail "monitor scaling explicit 3x remains available"
grep -Fx 'local omarchy_monitor_scale = 3' "$monitor_lua" >/dev/null || fail "monitor scaling explicit 3x persists"
grep -Fx 'local omarchy_gdk_scale = 3' "$monitor_lua" >/dev/null || fail "monitor scaling explicit 3x persists GDK scale"
pass "monitor scaling explicit 3x remains available"

# GTK only honors integer GDK_SCALE, so fractional monitor scales persist a
# rounded GDK scale.
write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -F 'scale = 1.6' "$eval_out" >/dev/null || fail "monitor scaling explicit 1.6x remains available"
grep -Fx 'local omarchy_monitor_scale = 1.6' "$monitor_lua" >/dev/null || fail "monitor scaling explicit 1.6x persists"
grep -Fx 'local omarchy_gdk_scale = 2' "$monitor_lua" >/dev/null || fail "monitor scaling 1.6x persists integer GDK scale 2"
pass "monitor scaling 1.6x persists integer GDK scale 2"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.25
grep -Fx 'local omarchy_monitor_scale = 1.25' "$monitor_lua" >/dev/null || fail "monitor scaling explicit 1.25x persists"
grep -Fx 'local omarchy_gdk_scale = 1' "$monitor_lua" >/dev/null || fail "monitor scaling 1.25x persists integer GDK scale 1"
pass "monitor scaling 1.25x persists integer GDK scale 1"

scale=$(OMARCHY_TEST_MONITOR_SCALE=3 run_scaling)
[[ $scale == "3" ]] || fail "monitor scaling reports explicit 3x scale" "actual: $scale"
pass "monitor scaling reports explicit 3x scale"

scale=$(OMARCHY_TEST_MONITOR_SCALE=3.2 run_scaling)
[[ $scale == "3.2" ]] || fail "monitor scaling reports the actual non-preset scale" "actual: $scale"
pass "monitor scaling reports the actual non-preset scale"

# 1280x800 approximates the 3x preset as 3.2x.
write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling 3
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling approximates explicit 3x as 3.2x"
grep -Fx 'local omarchy_monitor_scale = 3.2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling persists approximated 3.2x"
pass "monitor scaling approximates explicit 3x as 3.2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling up
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling up reaches approximated 3.2x"
pass "monitor scaling up reaches approximated 3.2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=4 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling down
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling down reaches approximated 3.2x"
pass "monitor scaling down reaches approximated 3.2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=6016 OMARCHY_TEST_MONITOR_HEIGHT=3384 run_scaling 1.25
grep -F 'scale = 1.33333' "$eval_out" >/dev/null || fail "monitor scaling approximates explicit 1.25x"
pass "monitor scaling approximates explicit 1.25x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling 3.2
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling accepts displayed approximate values"
pass "monitor scaling accepts displayed approximate values"

# On a mode where both 3x and 4x resolve to 4x, the duplicate is one step.
write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=4 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=804 run_scaling down
grep -F 'scale = 2' "$eval_out" >/dev/null || fail "monitor scaling down skips duplicate 4x approximation"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling down persists 2x after skipping duplicate approximation"
pass "monitor scaling down skips duplicate approximation"

# A rule naming an output overrides the catch-all, so writing the catch-all
# leaves it stale and the reload that write triggers undoes the live change.

write_named_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 2 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@60", position = "auto-right", scale = 1 })
-- hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 4 })
LUA
}

write_named_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling writes onto the rule naming the focused output"
grep -Fx 'hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@60", position = "auto-right", scale = 1 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves another output's rule alone"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the catch-all alone once a named rule matched"
grep -Fx -e '-- hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 4 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves a commented-out rule alone"
pass "monitor scaling writes onto a named per-output rule"

# nwg-displays writes one field per line.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({
  output = "eDP-1",
  mode = "2880x1800@120",
  position = "0x0",
  scale = 2,
})
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx '  scale = 1.6,' "$monitor_lua" >/dev/null ||
  fail "monitor scaling rewrites the multi-line rule form"
pass "monitor scaling rewrites the multi-line rule form"

# A named rule may leave scale to the catch-all; it still has to be pinned here,
# or the reload puts the catch-all's value back.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", transform = 3 })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", transform = 3, scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling adds a scale to a named rule that has none"
pass "monitor scaling adds a scale to a named rule that has none"

# A hand-written rule spaces its keys however the author likes.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output  =  "eDP-1", mode = "preferred", position = "auto", scale = 2 })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output  =  "eDP-1", mode = "preferred", position = "auto", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling matches a named rule whose keys are spaced out"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the catch-all alone for a spaced-out named rule"
pass "monitor scaling matches a named rule whose keys are spaced out"

# Lua takes ; between table fields, and appending a comma after one is a syntax
# error Hyprland reports as a config that will not load.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "eDP-1"; mode = "preferred"; position = "auto"; })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "eDP-1"; mode = "preferred"; position = "auto"; scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a scale after a semicolon separator"
pass "monitor scaling appends a scale after a semicolon separator"

# A comment carries commas and braces of its own, and the field goes in the
# table rather than in the comment.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({
  output = "eDP-1",
  transform = 3, -- keep the panel rotated
})
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx '  transform = 3, scale = 1.6 -- keep the panel rotated' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a scale beside a commented field, not inside the comment"
pass "monitor scaling appends a scale beside a commented field"

cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "eDP-1", transform = 3 }) -- was { 1 }
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "eDP-1", transform = 3, scale = 1.6 }) -- was { 1 }' "$monitor_lua" >/dev/null ||
  fail "monitor scaling ignores a brace inside a trailing comment"
pass "monitor scaling ignores a brace inside a trailing comment"

# GDK_SCALE is one integer for the whole session. Following one display's scale
# while another is enabled resizes XWayland windows on the untouched display.
write_named_config
OMARCHY_TEST_SECOND_MONITOR=1 OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.25
grep -Fx 'local omarchy_gdk_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves GDK scale alone while a second display is enabled"
grep -F 'position = "0x0", scale = 1.25 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling still writes the per-output scale with two displays"
pass "monitor scaling leaves GDK scale alone with two displays enabled"

write_named_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.25
grep -Fx 'local omarchy_gdk_scale = 1' "$monitor_lua" >/dev/null ||
  fail "monitor scaling still tracks GDK scale on a single display"
pass "monitor scaling still tracks GDK scale on a single display"

# monitors.lua is commonly a symlink into a dotfiles repo. Replacing the link
# with a regular file detaches the config from the repo without saying so.
real_lua="$test_tmp/dotfiles-monitors.lua"
write_named_config
mv "$monitor_lua" "$real_lua"
ln -s "$real_lua" "$monitor_lua"
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
[[ -L $monitor_lua ]] || fail "monitor scaling keeps a symlinked monitors.lua a symlink"
grep -F 'position = "0x0", scale = 1.6 })' "$real_lua" >/dev/null ||
  fail "monitor scaling writes through a symlinked monitors.lua"
pass "monitor scaling keeps a symlinked monitors.lua a symlink"
rm -f "$monitor_lua"

# A config that cannot be read is not a config with no rule for this output.
# Taking the two for the same thing sends an unwritable setup down the
# catch-all branch, which rewrites the shared scale and reports success.
if (( EUID != 0 )); then
  write_named_config
  chmod 000 "$monitor_lua"
  if OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6 2>/dev/null; then
    chmod 644 "$monitor_lua"
    fail "monitor scaling reports failure when monitors.lua cannot be read"
  fi
  chmod 644 "$monitor_lua"
  grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
    fail "monitor scaling leaves the catch-all alone when monitors.lua cannot be read"
  pass "monitor scaling reports failure when monitors.lua cannot be read"
fi

# A rule inside a --[[ ]] block is commented out. Rewriting a scale in there
# reports a rule was written, and the caller then leaves the catch-all alone
# too, so the change is persisted nowhere and the reload undoes it.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
--[[
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 4 })
]]
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 4 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves a rule inside a block comment alone"
grep -Fx 'local omarchy_monitor_scale = 1.6' "$monitor_lua" >/dev/null ||
  fail "monitor scaling falls back to the catch-all when the only named rule is block commented"
pass "monitor scaling leaves a rule inside a block comment alone"

# desc: is Hyprland's own syntax and the usual advice for multi-monitor setups,
# because connector names renumber across hotplug. A desc: rule that goes
# unrecognised sends the write to the catch-all, which here is read by the rule
# for the other output.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.monitor({ output = "desc:BOE NE180WUM", mode = "preferred", position = "0x0", scale = 2 })
hl.monitor({ output = "desc:LG Electronics LG HDR 4K", mode = "preferred", position = "auto-right", scale = 1 })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "desc:BOE NE180WUM", mode = "preferred", position = "0x0", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling writes onto a rule naming the output by desc:"
grep -Fx 'hl.monitor({ output = "desc:LG Electronics LG HDR 4K", mode = "preferred", position = "auto-right", scale = 1 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves another output's desc: rule alone"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the catch-all alone once a desc: rule matched"
pass "monitor scaling writes onto a rule naming the output by desc:"

# Hyprland trims the desc: selector before comparing, so a rule that spaces one
# out does name the output. Missing it here sends the write to the catch-all
# the reload then overrides, which is the defect this command exists to remove.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.monitor({ output = "desc:  BOE NE180WUM  ", mode = "preferred", position = "0x0", scale = 2 })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "desc:  BOE NE180WUM  ", mode = "preferred", position = "0x0", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling matches a desc: selector whose spacing Hyprland trims"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the catch-all alone for a spaced-out desc: rule"
pass "monitor scaling matches a desc: selector whose spacing Hyprland trims"

# A desc: prefix cut mid-parenthesis is ordinary selector text to Hyprland. Read
# as a table delimiter it leaves the rule open, so every rule below it goes
# unseen and the catch-all is rewritten as if none of them named this output.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.monitor({ output = "desc:LG Electronics (LG HDR", mode = "preferred", position = "auto-right", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2 })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling reads past a bracket inside a quoted value"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the catch-all alone past a bracket inside a quoted value"
pass "monitor scaling reads past a bracket inside a quoted value"

# The shared variable is only the catch-all when a catch-all rule reads it. A
# connector name that has gone stale across a renumber leaves no rule naming
# the focused output, and writing the variable then resizes whichever display
# does read it.
cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })
hl.monitor({ output = "DP-9", mode = "preferred", position = "auto", scale = 1 })
LUA
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -F 'scale = 1.6' "$eval_out" >/dev/null ||
  fail "monitor scaling still applies the scale with no rule naming the output"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves a scale variable another output's rule reads alone"
pass "monitor scaling leaves a scale variable another output's rule reads alone"
