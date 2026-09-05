#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
log_file="$tmpdir/hyprctl.log"
notification_log="$tmpdir/notification.log"
mkdir -p "$stub_dir" "$home_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash

if [[ $1 == "activeworkspace" && -n $HYPRCTL_BROKEN ]]; then
  printf '{}\n'
elif [[ $1 == "getoption" ]]; then
  printf '{"option":"scrolling:direction","str":"%s","set":false}\n' "${FAKE_DEFAULT_DIRECTION:-right}"
elif [[ $1 == "activeworkspace" && $FAKE_LAYOUT == "absent" ]]; then
  printf '{"id":3}\n'
elif [[ $1 == "activeworkspace" ]]; then
  printf '{"id":3,"tiledLayout":"%s"}\n' "${FAKE_LAYOUT:-dwindle}"
elif [[ $1 == "eval" && -n $HYPRCTL_EVAL_FAILS ]]; then
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
  exit 7
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
fi
EOF
chmod +x "$stub_dir/hyprctl"

cat >"$stub_dir/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFICATION_LOG"
EOF
chmod +x "$stub_dir/omarchy-notification-send"

layout_file="$home_dir/.local/state/omarchy/workspace-layouts/3.lua"

# bootstrap.lua builds package.path from $HOME, so XDG_STATE_HOME has to match
# the sandbox or the developer's own state directory leaks into the run.
run_command() {
  local command=$1
  shift
  env HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" OMARCHY_PATH="$ROOT" \
    HYPRCTL_LOG="$log_file" NOTIFICATION_LOG="$notification_log" \
    PATH="$stub_dir:$PATH" "$@" "$ROOT/bin/$command"
}

run_command omarchy-hyprland-workspace-layout-toggle

[[ -f $layout_file ]] || fail "workspace layout toggle saves a workspace rule"
grep -Fx 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })' "$layout_file" >/dev/null ||
  fail "workspace layout toggle saves the selected layout"
grep -Fx 'eval hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "right" } })' "$log_file" >/dev/null ||
  fail "workspace layout toggle applies the selected layout immediately"
pass "workspace layout toggle persists and applies the selected layout"

if run_command omarchy-hyprland-workspace-layout-toggle HYPRCTL_BROKEN=1 2>/dev/null; then
  fail "workspace layout toggle exits nonzero without a workspace id"
fi
[[ -f "$home_dir/.local/state/omarchy/workspace-layouts/null.lua" ]] &&
  fail "workspace layout toggle does not persist a rule without a workspace id"
pass "workspace layout toggle ignores broken hyprctl output"

: >"$log_file"
before=$(cat "$layout_file")
run_command omarchy-hyprland-window-split-toggle
grep -Fx 'dispatch hl.dsp.layout("togglesplit")' "$log_file" >/dev/null ||
  fail "split toggle uses togglesplit on dwindle"
[[ $(cat "$layout_file") == "$before" ]] ||
  fail "split toggle leaves the saved rule alone on dwindle"
pass "split toggle uses togglesplit on dwindle"

: >"$log_file"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=scrolling
grep -Fx 'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "down" } })' "$layout_file" >/dev/null ||
  fail "split toggle saves a vertical scrolling direction"
grep -Fx 'eval hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "down" } })' "$log_file" >/dev/null ||
  fail "split toggle applies a vertical scrolling direction immediately"
pass "split toggle turns scrolling vertical"

: >"$log_file"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=scrolling
grep -Fx 'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "right" } })' "$layout_file" >/dev/null ||
  fail "split toggle flips a vertical scrolling direction back to horizontal"
pass "split toggle flips scrolling back to horizontal"

# Two assertions, not one: hl.workspace_rule merges, so dropping the direction
# from the file leaves it applied until a reload unless the reset is sent live.
: >"$log_file"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=scrolling
run_command omarchy-hyprland-workspace-layout-toggle FAKE_LAYOUT=scrolling
grep -Fx 'hl.workspace_rule({ workspace = "3", layout = "dwindle" })' "$layout_file" >/dev/null ||
  fail "a layout change drops the saved axis"
grep -Fx 'eval hl.workspace_rule({ workspace = "3", layout = "dwindle", layout_opts = { direction = "right" } })' "$log_file" >/dev/null ||
  fail "a layout change resets the live axis rather than leaving it merged on"
pass "a layout change forgets the axis"

: >"$log_file"
run_command omarchy-hyprland-workspace-layout-toggle FAKE_LAYOUT=dwindle FAKE_DEFAULT_DIRECTION=up
grep -Fx 'eval hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "up" } })' "$log_file" >/dev/null ||
  fail "the reset honours a configured scrolling direction"
pass "the reset honours a configured scrolling direction"

: >"$log_file"
run_command omarchy-hyprland-workspace-layout-toggle FAKE_LAYOUT=scrolling FAKE_DEFAULT_DIRECTION=sideways
grep -Fx 'eval hl.workspace_rule({ workspace = "3", layout = "dwindle" })' "$log_file" >/dev/null ||
  fail "an unusable default direction is left out of the rule"
pass "an unusable default direction is left out of the rule"

: >"$log_file"
: >"$notification_log"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=master
[[ -s $log_file ]] && fail "split toggle does not dispatch on an unsupported layout"
grep -F 'The master layout has no split direction' "$notification_log" >/dev/null ||
  fail "split toggle explains an unsupported layout"
pass "split toggle explains an unsupported layout"

# Replay what the split toggle writes, not whatever the tests above left.
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=scrolling
HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" OMARCHY_PATH="$ROOT" lua - <<'LUA'
local rules = {}

hl = {
  workspace_rule = function(rule)
    table.insert(rules, rule)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.workspace-layouts")

assert(#rules == 1)
assert(rules[1].workspace == "3")
assert(rules[1].layout == "scrolling")
assert(rules[1].layout_opts.direction == "down")
LUA
(( $? == 0 )) || fail "saved workspace layouts load into Hyprland configuration"
pass "saved workspace layouts load into Hyprland configuration"

# Two directions folded into one Lua string would break every reload: these are
# replayed with a bare require().
printf '%s\n%s\n' \
  'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "down" } })' \
  'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "right" } })' \
  >"$layout_file"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=scrolling
# Whole-file, not a grep: the seeded second line is byte-identical to what a
# correct run writes, so a script that wrote nothing would pass a match.
[[ $(cat "$layout_file") == 'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "right" } })' ]] ||
  fail "a duplicated rule reads as its first direction"
pass "a duplicated rule reads as its first direction"

printf 'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "sideways" } })\n' >"$layout_file"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=scrolling
grep -Fx 'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "down" } })' "$layout_file" >/dev/null ||
  fail "an unrecognized direction is ignored"
pass "an unrecognized direction is ignored"

: >"$log_file"
printf 'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "down" } })\n' >"$layout_file"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=scrolling HYPRCTL_EVAL_FAILS=1
grep -Fx 'keyword workspace 3, layout:scrolling, layoutopt:direction:right' "$log_file" >/dev/null ||
  fail "the keyword fallback carries the direction"
pass "the keyword fallback carries the direction"

: >"$log_file"
: >"$notification_log"
run_command omarchy-hyprland-window-split-toggle FAKE_LAYOUT=absent
grep -Fx 'dispatch hl.dsp.layout("togglesplit")' "$log_file" >/dev/null ||
  fail "a Hyprland without tiledLayout keeps togglesplit"
[[ -s $notification_log ]] && fail "a Hyprland without tiledLayout sends no notification"
pass "a Hyprland without tiledLayout keeps togglesplit"

fresh_home="$tmpdir/fresh"
mkdir -p "$fresh_home"
fresh_errors="$tmpdir/fresh.err"
env HOME="$fresh_home" XDG_STATE_HOME="$fresh_home/.local/state" OMARCHY_PATH="$ROOT" \
  HYPRCTL_LOG="$log_file" NOTIFICATION_LOG="$notification_log" PATH="$stub_dir:$PATH" \
  FAKE_LAYOUT=scrolling "$ROOT/bin/omarchy-hyprland-window-split-toggle" 2>"$fresh_errors"
[[ $(cat "$fresh_home/.local/state/omarchy/workspace-layouts/3.lua" 2>/dev/null) == 'hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "down" } })' ]] ||
  fail "the first press creates the state directory and rule"
# A keybinding has no terminal, so a missing rule file must not spill to stderr.
[[ -s $fresh_errors ]] && fail "the first press reads no missing file" "$(cat "$fresh_errors")"
pass "the first press creates the state directory and rule"
