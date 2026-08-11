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

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  # eDP-1 is focused; DP-1 stands in for a second display the panel can target
  # with --monitor without walking over to it, and for the neighbour a rescaled
  # display can collide with.
  printf '[{"name":"eDP-1","focused":true,"description":"Acme Internal 0x1234","scale":%s,"width":%s,"height":%s,"refreshRate":120.0,"x":%s,"y":%s},{"name":"DP-1","focused":false,"description":"Acme Wide 42 SN123","scale":1,"width":2560,"height":1440,"refreshRate":60.0,"x":%s,"y":0}]' \
    "${OMARCHY_TEST_MONITOR_SCALE:-2}" "${OMARCHY_TEST_MONITOR_WIDTH:-2880}" "${OMARCHY_TEST_MONITOR_HEIGHT:-1800}" \
    "${OMARCHY_TEST_MONITOR_X:-0}" "${OMARCHY_TEST_MONITOR_Y:-0}" "${OMARCHY_TEST_NEIGHBOUR_X:-4000}"
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >"$OMARCHY_TEST_HYPRCTL_EVAL_OUT"
else
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"

write_monitor_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
LUA
}

run_scaling() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_EVAL_OUT="$eval_out" \
    OMARCHY_TEST_MONITOR_SCALE="${OMARCHY_TEST_MONITOR_SCALE:-2}" \
    OMARCHY_TEST_MONITOR_X="${OMARCHY_TEST_MONITOR_X:-0}" \
    OMARCHY_TEST_MONITOR_Y="${OMARCHY_TEST_MONITOR_Y:-0}" \
    OMARCHY_TEST_NEIGHBOUR_X="${OMARCHY_TEST_NEIGHBOUR_X:-4000}" \
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

# --- --monitor targets a display other than the focused one ---

write_monitor_config
: >"$eval_out"
run_scaling --monitor DP-1 2
grep -F 'output = "DP-1"' "$eval_out" >/dev/null || fail "--monitor scales the named display"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "scaling a non-focused display leaves the shared default alone"
pass "--monitor scales the named display without rewriting the shared default"

# The catch-all in monitors.lua covers every display, so only the focused one
# may write it.
write_monitor_config
: >"$eval_out"
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling --monitor eDP-1 1
grep -F 'output = "eDP-1"' "$eval_out" >/dev/null || fail "--monitor accepts the focused display"
grep -Fx 'local omarchy_monitor_scale = 1' "$monitor_lua" >/dev/null ||
  fail "scaling the focused display still persists the shared default"
pass "--monitor on the focused display still persists"

# An empty output is Hyprland's catch-all, so an unknown name must never reach
# the eval — it would rescale every display instead of none.
write_monitor_config
: >"$eval_out"
run_scaling --monitor NOPE-1 2 && fail "an unknown --monitor exits non-zero"
[[ ! -s $eval_out ]] || fail "an unknown --monitor dispatches no eval"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "an unknown --monitor leaves monitors.lua alone"
pass "an unknown --monitor is refused before it can hit every display"

# --- reading a specific display's scale ---

[[ $(OMARCHY_TEST_MONITOR_SCALE=2 run_scaling --monitor DP-1) == "1" ]] ||
  fail "--monitor reports the named display's scale"
[[ $(OMARCHY_TEST_MONITOR_SCALE=2 run_scaling) == "2" ]] ||
  fail "no --monitor still reports the focused display's scale"
pass "--monitor reads the named display's scale"

# --- a display with a rule of its own has that rule rewritten ---

# A rule keyed to one display overrides the catch-all, so writing the catch-all
# would leave the rule applying the old scale. Worse than not persisting: the
# write reloads Hyprland, and the reload undoes what was just applied.

write_pinned_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x1000", scale = 2 })
hl.monitor({ output = "desc:Acme Wide 42", mode = "preferred", position = "1440x0", scale = 2 })

-- hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = 4 })
LUA
}

write_pinned_config
run_scaling 1.6
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x1000", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "the focused display's own rule carries the new scale"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "the catch-all is left alone when the display has a rule of its own"
pass "a display with a rule of its own has that rule rewritten, not the catch-all"

# The position and the mode are the user's, and a scale change is not a licence
# to move a display or restate its mode.
write_pinned_config
run_scaling 1.6
grep -F 'position = "0x1000"' "$monitor_lua" >/dev/null || fail "the pinned position survives"
grep -F 'mode = "preferred"' "$monitor_lua" >/dev/null || fail "the mode survives"
pass "rewriting a rule's scale leaves its position and mode untouched"

# --- a desc: rule is matched the way Hyprland matches it ---

# `desc:` matches by prefix, so an abbreviated description still names the
# display, and the identifier the user chose is what stays in the file.
write_pinned_config
run_scaling --monitor DP-1 1.6
grep -Fx 'hl.monitor({ output = "desc:Acme Wide 42", mode = "preferred", position = "1440x0", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "an abbreviated desc: rule is matched and keeps its identifier"
pass "a desc: rule is matched by prefix and keeps the identifier the user wrote"

# --- commented-out rules are not rules ---

# The shipped config carries commented examples. Matching one would rewrite a
# comment and leave the real configuration untouched.
write_pinned_config
run_scaling --monitor DP-1 1.6
grep -F -- '-- hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = 4 })' "$monitor_lua" >/dev/null ||
  fail "a commented example is left as written"
pass "a commented-out rule is not mistaken for a rule"

# --- a display with no rule of its own, targeted remotely ---

# The catch-all speaks for every display, so moving it would resize the rest.
write_monitor_config
run_scaling --monitor DP-1 1.6
grep -Fx 'hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "a remotely scaled display gains a rule of its own"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "the catch-all still speaks for the displays that have no rule"
pass "a display scaled from the selector gains its own rule, leaving the rest alone"

# --- GDK_SCALE follows only the display the user is on ---

# One value serves the whole session, so a display the user is not on does not
# get to redefine it.
write_monitor_config
run_scaling --monitor DP-1 1.6
grep -Fx 'local omarchy_gdk_scale = 2' "$monitor_lua" >/dev/null ||
  fail "scaling another display leaves GDK_SCALE alone"
pass "GDK_SCALE is left alone when the change is to a display the user is not on"

write_pinned_config
run_scaling 3
grep -Fx 'local omarchy_gdk_scale = 3' "$monitor_lua" >/dev/null ||
  fail "scaling the focused display still moves GDK_SCALE"
pass "GDK_SCALE still follows the focused display"

# --- appending a rule to a file that does not end in a newline ---

# The rule would otherwise land on the end of the last line, and a monitors.lua
# that does not parse takes the session's whole monitor configuration with it.
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = 2' >"$monitor_lua"
run_scaling --monitor DP-1 1.6
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "the last line survives an appended rule"
grep -Fx 'hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "the appended rule stands on its own line"
pass "a rule appended to a file with no trailing newline stays on its own line"

# --- scaling the same display twice does not accumulate rules ---

# The second change has to find the rule the first one wrote, or every
# adjustment leaves another rule behind and the last one silently wins.
write_monitor_config
run_scaling --monitor DP-1 1.6
run_scaling --monitor DP-1 1
(( $(grep -c 'output = "DP-1"' "$monitor_lua") == 1 )) ||
  fail "scaling a display twice leaves one rule"
grep -F 'scale = 1 }' "$monitor_lua" >/dev/null || fail "the surviving rule carries the latest scale"
pass "scaling the same display twice rewrites its rule instead of adding another"
