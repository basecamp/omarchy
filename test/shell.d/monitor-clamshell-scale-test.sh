#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
monitor_lua="$home_dir/.config/hypr/monitors.lua"
eval_log="$test_tmp/hyprctl-eval.log"
state_dir="$home_dir/.local/state/omarchy/toggles/hypr"
scale_state="$state_dir/internal-monitor-scale"

mkdir -p "$stub_bin" "$home_dir/.config/hypr"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "all" && $3 == "-j" ]]; then
  if [[ ${OMARCHY_TEST_INTERNAL_DISABLED:-false} == "true" ]]; then
    printf '[{"name":"eDP-1","disabled":true,"scale":null}]'
  else
    printf '[{"name":"eDP-1","disabled":false,"scale":%s}]' "${OMARCHY_TEST_INTERNAL_SCALE:-2}"
  fi
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >>"$OMARCHY_TEST_HYPRCTL_EVAL_LOG"
elif [[ $1 == "reload" ]]; then
  printf 'reload\n' >>"$OMARCHY_TEST_HYPRCTL_EVAL_LOG"
elif [[ $1 == "dispatch" ]]; then
  printf 'dispatch %s\n' "$2" >>"$OMARCHY_TEST_HYPRCTL_EVAL_LOG"
else
  exit 1
fi
SH

cat >"$stub_bin/omarchy-hyprland-monitor-internal" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-hyprland-monitor-internal-mirror" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
echo eDP-1
SH

cat >"$stub_bin/omarchy-hyprland-monitor-external-active" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_EXTERNAL_ACTIVE:-false} == "true" ]]
SH

cat >"$stub_bin/omarchy-hw-clamshell" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_CLAMSHELL:-false} == "true" ]]
SH

chmod +x "$stub_bin"/*

write_auto_monitor_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"
LUA
}

write_internal_monitor_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.25 })
hl.monitor({ output = "", mode = "preferred", position = "auto-right", scale = 1 })
LUA
}

# A specific-output rule that references the omarchy_monitor_scale variable
# (the default template's pattern) instead of a literal value. The variable
# must be resolved, not captured as the literal string "omarchy_monitor_scale".
write_internal_monitor_var_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 1.5
local omarchy_monitor_scale = 1.5
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
}

# An explicit non-numeric scale on the internal rule, alongside an unrelated
# omarchy_monitor_scale local that must not be substituted for it.
write_internal_monitor_auto_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = 2
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = "auto" })
LUA
}

# The internal rule names a local that does not exist. The catch-all rule below
# it never applies to an output that has its own rule, so it must not be read.
write_internal_monitor_unresolvable_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = my_scale })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# The shipped default: no rule for the internal panel, and the catch-all rule
# references the omarchy_monitor_scale local. Quoted here, and commented below.
write_catch_all_var_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = "1.5"
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
}

write_commented_catch_all_var_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = 1.25 -- HiDPI panel
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
}

# A position that references a local, the same pattern the scale key allows.
write_internal_monitor_position_var_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_position = "0x0"
hl.monitor({ output = "eDP-1", mode = "preferred", position = omarchy_monitor_position, scale = 1.25 })
LUA
}

# An internal rule that names no scale at all, so the catch-all supplies one.
write_internal_monitor_scaleless_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", transform = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# A local holding an expression rather than a scalar. Half of it is not a scale.
write_expression_scale_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = 3 / 2
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
}

# A local that happens to be named after a quoted scale value. The quotes make
# the rule's "auto" a string, so the local must not be substituted for it.
write_shadowed_auto_config() {
  cat >"$monitor_lua" <<'LUA'
local auto = 1.5
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = "auto" })
LUA
}

# An expression written straight into the rule rather than into a local.
write_expression_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 3 / 2 })
LUA
}

# Commented-out text after a rule is not a rule, and not one of its keys either.
write_commented_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = 1 }) -- output = "eDP-1"
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.5 })
LUA
}

write_commented_internal_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.25 }) -- scale = 3
LUA
}

# A nested table before the keys, and semicolons for separators. Both are Lua a
# user can reasonably write, and neither ends the rule.
write_nested_table_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", reserved_area = { top = 24 }, position = "0x0", scale = 1.25 })
LUA
}

write_block_comment_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", --[[ internal panel ]] position = "0x0", scale = 1.25 })
LUA
}

write_semicolon_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1"; position = "0x0"; scale = 1.25; transform = 1 })
LUA
}

remember_scale() {
  mkdir -p "$state_dir"
  printf '%s\n' "$1" >"$scale_state"
}

run_clamshell() {
  HOME="$home_dir" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_EVAL_LOG="$eval_log" \
    OMARCHY_TEST_INTERNAL_SCALE="${OMARCHY_TEST_INTERNAL_SCALE:-2}" \
    OMARCHY_TEST_INTERNAL_DISABLED="${OMARCHY_TEST_INTERNAL_DISABLED:-false}" \
    OMARCHY_TEST_EXTERNAL_ACTIVE="${OMARCHY_TEST_EXTERNAL_ACTIVE:-false}" \
    OMARCHY_TEST_CLAMSHELL="${OMARCHY_TEST_CLAMSHELL:-false}" \
    "$ROOT/bin/omarchy-hyprland-monitor-clamshell"
}

write_auto_monitor_config
: >"$eval_log"
OMARCHY_TEST_INTERNAL_SCALE=3 run_clamshell
grep -F 'scale = 2' "$eval_log" >/dev/null || fail "clamshell recovery ignores transient auto scale"
! grep -F 'scale = "auto"' "$eval_log" >/dev/null || fail "clamshell recovery does not apply auto scale"
[[ ! -f $scale_state ]] || fail "clamshell recovery does not remember transient scale"
pass "clamshell recovery ignores transient auto scale"

write_auto_monitor_config
: >"$eval_log"
OMARCHY_TEST_INTERNAL_SCALE=2 run_clamshell
! grep -F 'scale = ' "$eval_log" >/dev/null || fail "clamshell recovery does not reapply matching scale"
pass "clamshell recovery avoids redundant scale apply"

write_auto_monitor_config
: >"$eval_log"
OMARCHY_TEST_INTERNAL_SCALE=1.6 OMARCHY_TEST_EXTERNAL_ACTIVE=true OMARCHY_TEST_CLAMSHELL=true run_clamshell
[[ -f $scale_state ]] || fail "clamshell disable remembers internal scale"
[[ $(<"$scale_state") == "1.6" ]] || fail "clamshell disable remembers internal scale value"
pass "clamshell disable remembers internal scale"

: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.6' "$eval_log" >/dev/null || fail "clamshell recovery uses remembered internal scale"
! grep -F 'scale = "auto"' "$eval_log" >/dev/null || fail "clamshell recovery avoids auto after disabled internal display"
pass "clamshell recovery uses remembered internal scale"

write_internal_monitor_config
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'position = "0x0"' "$eval_log" >/dev/null || fail "clamshell recovery uses configured internal position"
grep -F 'scale = 1.25' "$eval_log" >/dev/null || fail "clamshell recovery uses configured internal scale"
pass "clamshell recovery uses configured internal monitor rule"

# Regression: specific-output rule referencing the omarchy_monitor_scale
# variable must resolve to the variable's value, not fall back to the default.
write_internal_monitor_var_config
rm -f "$scale_state"
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.5' "$eval_log" >/dev/null || fail "clamshell recovery resolves omarchy_monitor_scale variable reference"
pass "clamshell recovery resolves omarchy_monitor_scale variable reference"

# An explicit "auto" on the internal rule is a value, not a variable reference,
# so it must not pick up an unrelated omarchy_monitor_scale local.
write_internal_monitor_auto_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.75' "$eval_log" >/dev/null || fail "clamshell recovery keeps auto scale off the omarchy_monitor_scale local"
pass "clamshell recovery keeps auto scale off the omarchy_monitor_scale local"

# The catch-all rule does not apply to an output that has its own rule.
write_internal_monitor_unresolvable_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.75' "$eval_log" >/dev/null || fail "clamshell recovery ignores the catch-all rule when the internal panel has its own"
pass "clamshell recovery ignores the catch-all rule when the internal panel has its own"

write_catch_all_var_config
rm -f "$scale_state"
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.5' "$eval_log" >/dev/null || fail "clamshell recovery resolves a quoted scale through the catch-all rule"
pass "clamshell recovery resolves a quoted scale through the catch-all rule"

write_commented_catch_all_var_config
rm -f "$scale_state"
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.25' "$eval_log" >/dev/null || fail "clamshell recovery ignores a trailing comment on the scale local"
pass "clamshell recovery ignores a trailing comment on the scale local"

write_internal_monitor_position_var_config
rm -f "$scale_state"
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'position = "0x0"' "$eval_log" >/dev/null || fail "clamshell recovery resolves a position variable reference"
pass "clamshell recovery resolves a position variable reference"

# An internal rule that names no scale leaves the catch-all to supply one. Only
# a rule that names a scale keeps the catch-all away from the internal panel.
write_internal_monitor_scaleless_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1' "$eval_log" >/dev/null || fail "clamshell recovery takes the catch-all scale when the internal rule omits one"
! grep -F 'scale = 1.75' "$eval_log" >/dev/null || fail "clamshell recovery prefers the catch-all scale over the remembered one"
pass "clamshell recovery takes the catch-all scale when the internal rule omits one"

# Half of `3 / 2` is not the scale the user asked for.
write_expression_scale_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.75' "$eval_log" >/dev/null || fail "clamshell recovery leaves an expression scale unresolved"
pass "clamshell recovery leaves an expression scale unresolved"

# A quoted value is a string, not a reference to a local of the same name.
write_shadowed_auto_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.75' "$eval_log" >/dev/null || fail "clamshell recovery does not resolve a quoted scale against a local"
pass "clamshell recovery does not resolve a quoted scale against a local"

# Half of `3 / 2` is no better inside the rule than inside a local.
write_expression_rule_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.75' "$eval_log" >/dev/null || fail "clamshell recovery leaves an expression scale in a rule unresolved"
pass "clamshell recovery leaves an expression scale in a rule unresolved"

# A commented-out output must not pass for a rule the internal panel owns.
write_commented_rule_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.5' "$eval_log" >/dev/null || fail "clamshell recovery does not read a rule out of a trailing comment"
pass "clamshell recovery does not read a rule out of a trailing comment"

# Nor must a commented-out key displace the real one.
write_commented_internal_rule_config
remember_scale 1.75
: >"$eval_log"
OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
grep -F 'scale = 1.25' "$eval_log" >/dev/null || fail "clamshell recovery does not read a scale out of a trailing comment"
pass "clamshell recovery does not read a scale out of a trailing comment"

for config in nested_table semicolon block_comment; do
  "write_${config}_config"
  remember_scale 1.75
  : >"$eval_log"
  OMARCHY_TEST_INTERNAL_DISABLED=true run_clamshell
  grep -F 'position = "0x0"' "$eval_log" >/dev/null || fail "clamshell recovery reads the position out of a ${config//_/ } rule"
  grep -F 'scale = 1.25' "$eval_log" >/dev/null || fail "clamshell recovery reads the scale out of a ${config//_/ } rule"
  pass "clamshell recovery reads a ${config//_/ } rule"
done
