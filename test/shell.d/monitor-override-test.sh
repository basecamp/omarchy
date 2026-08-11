#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
state_home="$test_tmp/state"
state_json="$state_home/omarchy/display-overrides.json"
rules_lua="$state_home/omarchy/toggles/hypr/display-overrides.lua"

mkdir -p "$stub_bin"

# DP-1 reports an EDID description, so it is keyed by that and its setting
# follows the display between ports. HEADLESS-1 reports none and falls back to
# its connector name.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "monitors" && $2 == "all" && $3 == "-j" ]]; then
  printf '[{"name":"DP-1","description":"Acme Wide 42 SN123","x":1440,"y":0},{"name":"HEADLESS-1","description":"","x":0,"y":0}]'
else
  exit 1
fi
SH
chmod +x "$stub_bin"/*

run_override() {
  XDG_STATE_HOME="$state_home" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-hyprland-monitor-override" "$@"
}

reset_state() {
  rm -rf "$state_home"
}

# --- displays are keyed by description, falling back to connector name ---

reset_state
[[ $(run_override key DP-1) == "desc:Acme Wide 42 SN123" ]] ||
  fail "a display with a description is keyed by it"
[[ $(run_override key HEADLESS-1) == "HEADLESS-1" ]] ||
  fail "a display without a description falls back to its connector name"
pass "displays are keyed by description, falling back to connector name"

# --- a switched-off display is recorded and rendered ---

# This file carries the toggles Omarchy has always kept outside the user's
# config — a display switched off at runtime. Geometry lives in the user's own
# monitors.lua, so nothing here describes position, scale or rotation.
reset_state
run_override set DP-1 disabled true
grep -Fx 'hl.monitor({ output = "desc:Acme Wide 42 SN123", disabled = true })' "$rules_lua" >/dev/null ||
  fail "a switched-off display renders the flag against its stable key"
[[ $(run_override get DP-1 disabled) == "true" ]] || fail "the setting reads back"
pass "a switched-off display is recorded and rendered"

reset_state
run_override set DP-1 disabled true
run_override set HEADLESS-1 disabled true
[[ $(grep -c 'hl.monitor' "$rules_lua") == "2" ]] || fail "each display renders exactly one rule"
pass "each display renders exactly one rule"

# --- geometry is not this file's business ---

reset_state
run_override set DP-1 scale 2 2>/dev/null && fail "scale is refused"
run_override set DP-1 position 0x0 2>/dev/null && fail "position is refused"
run_override set DP-1 transform 1 2>/dev/null && fail "rotation is refused"
[[ ! -f $state_json ]] || fail "a refused property writes no state"
pass "geometry belongs in the user's config, not here"

# --- clearing ---

reset_state
run_override set DP-1 disabled true
run_override clear DP-1 disabled
[[ -z $(run_override get DP-1 disabled) ]] || fail "clearing a setting removes it"
[[ $(jq -r 'length' "$state_json") == "0" ]] || fail "a display with nothing left is dropped"
! grep -q 'hl.monitor' "$rules_lua" || fail "an empty state renders no rules"
pass "clearing a setting drops the display's entry with it"

reset_state
run_override set DP-1 disabled true
run_override set HEADLESS-1 disabled true
run_override clear DP-1
[[ -z $(run_override get DP-1 disabled) ]] || fail "clearing a display removes its entry"
[[ $(run_override get HEADLESS-1 disabled) == "true" ]] || fail "clearing one display leaves the others"
pass "clearing a display leaves the others alone"

# --- the locations this file replaced are still recognised ---

# A machine part-way through the move must recover the same as one that has
# finished, so both the per-display flag files and the internal display's own
# are still read and cleared.
reset_state
mkdir -p "$state_home/omarchy/toggles/hypr"
printf 'hl.monitor({ output = "eDP-1", disabled = true })\n' >"$state_home/omarchy/toggles/hypr/internal-monitor-disable.lua"
run_override is-disabled eDP-1 || fail "a legacy internal-display flag still reads as switched off"
run_override clear-disabled eDP-1
[[ ! -f "$state_home/omarchy/toggles/hypr/internal-monitor-disable.lua" ]] ||
  fail "clearing removes the legacy internal-display flag"
pass "the legacy internal-display flag is still read and cleared"

reset_state
mkdir -p "$state_home/omarchy/toggles/hypr"
printf 'hl.monitor({ output = "DP-1", disabled = true })\n' >"$state_home/omarchy/toggles/hypr/monitor-DP-1-disable.lua"
run_override is-disabled DP-1 || fail "a legacy per-display flag still reads as switched off"
run_override clear-disabled DP-1
[[ ! -f "$state_home/omarchy/toggles/hypr/monitor-DP-1-disable.lua" ]] ||
  fail "clearing removes the legacy per-display flag"
pass "the legacy per-display flag is still read and cleared"

# --- refusals ---

reset_state
run_override set DP-1 nonsense 1 2>/dev/null && fail "an unknown property exits non-zero"
run_override set DP-1 disabled 2>/dev/null && fail "a missing value exits non-zero"
run_override bogus DP-1 2>/dev/null && fail "an unknown action exits non-zero"
[[ ! -f $state_json ]] || fail "a refused call writes no state"
pass "unknown properties and actions are refused"
