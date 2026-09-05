#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The clamshell command's assumptions about Hyprland (docs/clamshell.md, A1-A6),
# checked against a real one. Two headless outputs stand in for the panel and
# the external monitor; the two hardware predicates are stubbed, since a VM has
# no lid; everything that reaches Hyprland is real. Each transition is made by
# the real command, and the panel must come back as it was: every field the
# config determines exactly, and an auto position as Hyprland's fresh, but
# deterministic, layout of the enabled outputs.

internal="eDP-1"
external="HDMI-A-1"
monitor_lua="$HOME/.config/hypr/monitors.lua"
overlay="$HOME/.local/state/omarchy/toggles/hypr/internal-monitor-clamshell.lua"
expected_overlay="hl.monitor({ output = \"$internal\", disabled = true })"

work=$(mktemp -d)
stub_bin="$work/bin"
backup=""
created=()
watcher_paused=0

# The lid reads a file the test flips; external monitors are always connected.
mkdir -p "$stub_bin"
printf '#!/bin/bash\n[[ $(< "%s/lid") == "closed" ]]\n' "$work" >"$stub_bin/omarchy-hw-laptop-closed"
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-hw-external-monitors"
chmod +x "$stub_bin"/*
printf 'open' >"$work/lid"

output_present() {
  hyprctl monitors all -j | jq -e --arg name "$1" '.[] | select(.name == $name)' >/dev/null
}

panel() {
  hyprctl monitors all -j | jq -c --arg name "$internal" '[.[] | select(.name == $name)] | first // empty'
}

panel_enabled() { [[ $(panel | jq -r '.disabled') == "false" ]]; }
panel_disabled() { [[ $(panel | jq -r '.disabled') == "true" ]]; }
panel_upright() { [[ $(panel | jq -r '.transform') == "0" ]]; }

snapshot() {
  panel | jq -c '{scale, x, y, width, height, refreshRate, transform, disabled}'
}

# An auto position is not a stored slot: Hyprland lays the enabled outputs out
# afresh on every reload, so a panel disabled out of the middle of an auto row
# comes back at its end — identically under the previous command, and after a
# physical replug. For auto shapes the fields the config determines must come
# back exactly and the arrangement must be deterministic; only an explicit
# position must come back in place.
snapshot_sans_position() {
  panel | jq -c '{scale, width, height, refreshRate, transform, disabled}'
}

# Reload applies asynchronously: poll for the expected state, bounded.
await() {
  local attempt
  for ((attempt = 0; attempt < 25; attempt++)); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

set_lid() { printf '%s' "$1" >"$work/lid"; }

run_command() {
  PATH="$stub_bin:$PATH" omarchy-hyprland-monitor-clamshell
}

apply_config() {
  cat >"$monitor_lua"
  hyprctl reload >/dev/null
}

cleanup() {
  trap - EXIT
  if [[ -n $backup ]]; then
    cp "$backup" "$monitor_lua"
  elif [[ -e $work/config-written ]]; then
    rm -f "$monitor_lua"
  fi
  rm -f "$overlay"
  hyprctl reload >/dev/null 2>&1 || true
  if [[ -e $work/config-written ]]; then
    await output_present "$internal" || true
  fi
  local name
  for name in "${created[@]}"; do
    hyprctl output remove "$name" >/dev/null 2>&1 || true
  done
  if (( watcher_paused )); then
    pkill -CONT -f omarchy-hyprland-monitor-watch >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

! omarchy-hw-laptop || fail "the clamshell acceptance test runs on a machine without a lid"

# The watcher runs the same command on every monitor event with the real lid
# predicate, which in a VM answers open; disabling the panel is such an event.
# It stands still while the test flips the stubbed lid.
if pkill -STOP -f omarchy-hyprland-monitor-watch >/dev/null 2>&1; then
  watcher_paused=1
fi

# A6: outputs under chosen names.
for name in "$internal" "$external"; do
  if ! output_present "$name"; then
    hyprctl output create headless "$name" >/dev/null || fail "A6: a headless output can be created as $name"
    created+=("$name")
  fi
done
await output_present "$internal" || fail "A6: a headless output can be created as $internal"
[[ $(omarchy-hyprland-monitor-laptop) == "$internal" ]] || fail "A6: the internal-panel predicate answers $internal" "$(omarchy-hyprland-monitor-laptop)"
omarchy-hyprland-monitor-external-active || fail "A6: an external output is active"
pass "A6: headless outputs stand in for the panel and the external monitor"

if [[ -e $monitor_lua ]]; then
  backup="$work/monitors.lua.prior"
  cp "$monitor_lua" "$backup"
fi
: >"$work/config-written"

description=$(panel | jq -r '.description // ""')
catch_all='hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })'

# Procedure A: for a config that leaves the panel enabled, disable it through
# the command, enable it through the command, and compare the panel field for
# field with what it was. These test Hyprland's reading of each shape, not ours.
round_trip() {
  local case="$1" positions="${2:-auto}" before after second
  apply_config
  await panel_enabled || fail "A2 ($case): the panel is enabled under the config" "$(panel)"
  sleep 1
  before=$(snapshot)
  screenshot "success-clamshell-$case-baseline"

  set_lid closed
  run_command || fail "A2 ($case): the command runs into clamshell"
  await panel_disabled || fail "A2 ($case): the overlay disables the panel" "$(panel)"
  [[ -f $overlay && $(< "$overlay") == "$expected_overlay" ]] || fail "I1 ($case): the overlay is exactly the disable rule" "$(cat "$overlay" 2>/dev/null)"
  screenshot "success-clamshell-$case-clamshell"

  set_lid open
  run_command || fail "A2 ($case): the command runs out of clamshell"
  await panel_enabled || fail "A2 ($case): a reload without the overlay enables the panel" "$(panel)"
  [[ ! -e $overlay ]] || fail "I2 ($case): the overlay is gone out of clamshell"
  sleep 1
  after=$(snapshot)
  if [[ $positions == exact ]]; then
    [[ $after == "$before" ]] || fail "A3 ($case): the panel comes back as it was" "before: $before
after:  $after"
  else
    [[ $(jq -c 'del(.x, .y)' <<<"$after") == $(jq -c 'del(.x, .y)' <<<"$before") ]] || fail "A3 ($case): scale, mode, refresh and transform come back as they were" "before: $before
after:  $after"
    set_lid closed
    run_command || fail "A3 ($case): a second cycle enters clamshell"
    await panel_disabled || fail "A3 ($case): a second cycle disables the panel" "$(panel)"
    set_lid open
    run_command || fail "A3 ($case): a second cycle leaves clamshell"
    await panel_enabled || fail "A3 ($case): a second cycle enables the panel" "$(panel)"
    sleep 1
    second=$(snapshot)
    [[ $second == "$after" ]] || fail "A3 ($case): a second cycle reproduces the same arrangement" "first:  $after
second: $second"
  fi
  screenshot "success-clamshell-$case-restored"
  pass "A2, A3 ($case): the panel round-trips and comes back as it was: $after"
}

round_trip catch-all <<LUA
$catch_all
LUA

round_trip explicit-scale <<LUA
hl.monitor({ output = "$internal", mode = "preferred", position = "auto", scale = 1.5 })
$catch_all
LUA

round_trip multiline <<LUA
hl.monitor({
  output = "$internal",
  mode = "preferred",
  position = "auto",
  scale = 1.25,
})
$catch_all
LUA

round_trip local-key <<LUA
local panel = "$internal"
local panel_scale = 1.25
hl.monitor({ output = panel, mode = "preferred", position = "auto", scale = panel_scale })
$catch_all
LUA

round_trip position exact <<LUA
hl.monitor({ output = "$internal", mode = "preferred", position = "100x50", scale = 1 })
hl.monitor({ output = "$external", mode = "preferred", position = "2100x0", scale = 1 })
LUA

round_trip mode <<LUA
hl.monitor({ output = "$internal", mode = "1280x720@60", position = "auto", scale = 1 })
$catch_all
LUA

round_trip one-line <<LUA
hl.monitor({ output = "$internal", scale = 1.25 }) hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
LUA

round_trip split-call <<LUA
hl
  .monitor({ output = "$internal", scale = 1.25 })
$catch_all
LUA

if [[ -n $description ]]; then
  round_trip description <<LUA
hl.monitor({ output = "desc:$description", mode = "preferred", position = "auto", scale = 1.25 })
$catch_all
LUA
else
  pass "description: skipped, the headless output reports no description"
fi

round_trip transform <<LUA
hl.monitor({ output = "$internal", mode = "preferred", position = "auto", scale = 1, transform = 1 })
$catch_all
LUA

# A1: the rotated rule does not survive into a config without it.
apply_config <<LUA
$catch_all
LUA
await panel_upright || fail "A1: rules do not accumulate across reloads" "$(panel)"
pass "A1: a reload rebuilds the rules; the transform of the previous config is gone"

# Procedure B: the user's own rule disables the panel. The overlay is placed in
# clamshell and removed out of it, and the user's rule governs throughout.
apply_config <<LUA
hl.monitor({ output = "$internal", disabled = true })
$catch_all
LUA
await panel_disabled || fail "B: the user's rule disables the panel" "$(panel)"
before=$(snapshot)
set_lid closed
run_command || fail "B: the command runs into clamshell"
[[ -f $overlay && $(< "$overlay") == "$expected_overlay" ]] || fail "B: the overlay is placed over the user's rule"
sleep 2
panel_disabled || fail "B: the panel stays disabled in clamshell" "$(panel)"
set_lid open
run_command || fail "B: the command runs out of clamshell"
[[ ! -e $overlay ]] || fail "B: the overlay is removed out of clamshell"
sleep 2
panel_disabled || fail "B: the user's rule keeps the panel disabled out of clamshell" "$(panel)"
[[ $(snapshot) == "$before" ]] || fail "B: the disabled panel is as it was" "before: $before
after:  $(snapshot)"
screenshot "success-clamshell-user-disabled"
pass "B: a panel the user disabled stays disabled through clamshell and out of it"

# A5, as measured: hyprctl reload exits 0 even when Lua rejects monitors.lua —
# the error surfaces only in configerrors, and the toggles directory still
# loads, so the overlay transition takes effect beside the broken config.
# Rollback under I3 therefore fires on an unreachable or hung reload, not on a
# Lua error in the user's config. Asserted so a Hyprland that starts failing
# the reload instead shows up here — and the transition half is asserted too:
# both command-driven transitions are made under the rejected config.
apply_config <<LUA
$catch_all
LUA
await panel_enabled || fail "A5: the panel is enabled before the config breaks" "$(panel)"
printf 'local x = (\n' >"$monitor_lua"
status=0
hyprctl reload >/dev/null 2>&1 || status=$?
errors=$(hyprctl configerrors 2>/dev/null || true)
(( status == 0 )) || fail "A5: hyprctl reload exits 0 on a config Hyprland rejects" "exit $status"
[[ $errors == *monitors.lua* ]] || fail "A5: configerrors names the rejected config" "$errors"
set_lid closed
run_command || fail "A5: the command runs into clamshell beside the rejected config"
await panel_disabled || fail "A5: the overlay still disables the panel beside the rejected config" "$(panel)"
[[ -f $overlay && $(< "$overlay") == "$expected_overlay" ]] || fail "A5: the overlay is exact beside the rejected config" "$(cat "$overlay" 2>/dev/null)"
set_lid open
run_command || fail "A5: the command runs out of clamshell beside the rejected config"
await panel_enabled || fail "A5: removing the overlay still enables the panel beside the rejected config" "$(panel)"
[[ ! -e $overlay ]] || fail "A5: the overlay is gone beside the rejected config"
pass "A5: a rejected config reloads 'ok' with the error in configerrors, and the overlay transitions still apply beside it"

# The repair path, last so every earlier case keeps the normal topology.
# Every non-internal output is made inactive: the test's own HDMI-A-1 removed,
# the VM's Virtual-1 -- removable by nothing -- disabled at runtime with
# hyprctl eval (test scaffolding, never the command). Hyprland then runs its
# reserved FALLBACK placeholder, which the predicate must not count -- part of
# the case. From here the command runs through a forwarding hyprctl wrapper
# that logs each verb and execs the real binary, so the claimed effects --
# exactly one real reload per gated run, a wake only when the panel came back
# -- are observed, not inferred; Hyprland-facing behavior stays real.
hyprctl_log="$work/hyprctl.log"
cat >"$stub_bin/hyprctl" <<SH
#!/bin/bash
printf '%s\n' "\$1" >>"$hyprctl_log"
exec $(command -v hyprctl) "\$@"
SH
chmod +x "$stub_bin/hyprctl"
real_calls() { grep -c "^$1\$" "$hyprctl_log" || true; }
no_active_external() {
  local status=0
  PATH="$stub_bin:$PATH" omarchy-hyprland-monitor-external-active >/dev/null 2>&1 || status=$?
  (( status == 1 ))
}
virtual_disabled() { [[ $(hyprctl monitors all -j | jq -r '[.[] | select(.name == "Virtual-1")] | first | .disabled') == "true" ]]; }
# A strict enabled assertion: an absent output or an unreadable answer must
# fail the case, not pass as "not disabled".
virtual_enabled() { [[ $(hyprctl monitors all -j | jq -r '[.[] | select(.name == "Virtual-1")] | first | .disabled') == "false" ]]; }
# The placeholder itself, asserted rather than assumed: without this the
# predicate answering false below reads the same whether FALLBACK is there or
# Hyprland stopped making one.
fallback_enabled() { [[ $(hyprctl monitors all -j | jq -r '[.[] | select(.name == "FALLBACK")] | first | .disabled') == "false" ]]; }
eval_disable() { hyprctl eval "hl.monitor({ output = \"$1\", disabled = true })" >/dev/null 2>&1; }

apply_config <<LUA
$catch_all
LUA
await panel_enabled || fail "P1 repair: the panel is enabled at the start" "$(panel)"
hyprctl output remove "$external" >/dev/null 2>&1 || true
eval_disable Virtual-1
await virtual_disabled || fail "P1 repair: Virtual-1 can be disabled at runtime" "$(hyprctl monitors all -j | jq -c '[.[] | {name, disabled}]')"
no_active_external || fail "P1 repair: with no enabled non-internal output, the predicate answers the contracted false" "exit was not 1"

# The stranded state: the compositor holds the panel disabled, disk is empty.
# Hyprland's enabled FALLBACK placeholder is present; the predicate is
# asserted again against it.
eval_disable "$internal"
await panel_disabled || fail "P1 repair: the stranded state can be staged" "$(panel)"
await fallback_enabled || fail "P1 repair: Hyprland runs its enabled FALLBACK placeholder once no real output is left" "$(hyprctl monitors all -j | jq -c '[.[] | {name, disabled}]')"
no_active_external || fail "P1 repair: the FALLBACK placeholder is not an active external" "$(hyprctl monitors all -j | jq -c '[.[] | {name, disabled}]')"
rm -f "$overlay"
set_lid open
: >"$hyprctl_log"
run_command || fail "P1 repair: the command runs on the stranded state"
await panel_enabled || fail "P1 repair: the repair enables a stranded panel through a real reload" "$(panel)"
(( $(real_calls reload) == 1 && $(real_calls dispatch) == 1 )) || fail "P1 repair: exactly one real reload and one wake" "$(cat "$hyprctl_log")"
pass "P1 repair: a stranded panel with no active external is repaired by the real command -- one reload, one wake, observed"

# The conditional reload-per-invocation exception, pinned for real: a config
# disabling the panel and Virtual-1 stages the state with one reload -- both
# disabled, FALLBACK up -- and each of two runs provably enters the gate,
# spends exactly one observed reload, and never wakes. The repair's reload
# preserves the topology, so the second round is a genuine re-entry. Valid
# only on a fresh compositor session, which every harness run provides.
apply_config <<LUA
hl.monitor({ output = "$internal", disabled = true })
hl.monitor({ output = "Virtual-1", disabled = true })
$catch_all
LUA
await panel_disabled || fail "P1 repair (two-run): the config disables the panel" "$(panel)"
await virtual_disabled || fail "P1 repair (two-run): the config disables Virtual-1 too" "$(hyprctl monitors all -j | jq -c '[.[] | {name, disabled}]')"
for round in 1 2; do
  no_active_external || fail "P1 repair (two-run): the gate is provably open before run $round" "exit was not 1"
  : >"$hyprctl_log"
  run_command || fail "P1 repair (two-run): run $round completes"
  sleep 2
  panel_disabled || fail "P1 repair (two-run): the panel stays disabled after run $round" "$(panel)"
  (( $(real_calls reload) == 1 && $(real_calls dispatch) == 0 )) || fail "P1 repair (two-run): run $round spends exactly one reload and no wake" "$(cat "$hyprctl_log")"
done
pass "P1 repair: a config-disabled panel enters the gate on both runs, spends one observed reload each, and is never woken"

# The gate-closure variant, once: the config disables only the panel,
# Virtual-1 is eval-disabled so FALLBACK opens the gate; the repair's reload
# clears the eval, Virtual-1 returns, the config keeps the panel disabled --
# no wake, observed -- and the gate honestly closes.
apply_config <<LUA
hl.monitor({ output = "$internal", disabled = true })
$catch_all
LUA
await panel_disabled || fail "P1 repair (gate-closure): the config disables the panel" "$(panel)"
eval_disable Virtual-1
await virtual_disabled || fail "P1 repair (gate-closure): Virtual-1 can be disabled at runtime" "$(hyprctl monitors all -j | jq -c '[.[] | {name, disabled}]')"
no_active_external || fail "P1 repair (gate-closure): the repair gate is provably open" "exit was not 1"
: >"$hyprctl_log"
run_command || fail "P1 repair (gate-closure): the run completes"
await virtual_enabled || fail "P1 repair (gate-closure): the repair's reload brings Virtual-1 back" "$(hyprctl monitors all -j | jq -c '[.[] | {name, disabled}]')"
sleep 2
panel_disabled || fail "P1 repair (gate-closure): the config still governs the panel through the repair's reload" "$(panel)"
(( $(real_calls reload) == 1 && $(real_calls dispatch) == 0 )) || fail "P1 repair (gate-closure): one reload, no wake, observed" "$(cat "$hyprctl_log")"
PATH="$stub_bin:$PATH" omarchy-hyprland-monitor-external-active >/dev/null 2>&1 || fail "P1 repair (gate-closure): the gate closes once a real output is back"
pass "P1 repair: a config-disabled panel is never woken; the reload restores the other output and closes the gate"
screenshot "success-clamshell-repair"
