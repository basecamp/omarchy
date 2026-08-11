#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Display state lives in one overrides file, and a laptop panel switched off
# while docked and then undocked can only be rescued by the boot-time recovery
# reading it. That is the path where a mistake costs a black screen with no
# pointer to fix it with, so it is checked against a real installed system
# rather than only in unit tests with stubbed commands.
#
# The physical half of that story — unplugging an external display between one
# boot and the next — cannot be staged here: the recovery reads connector status
# straight from DRM, and a VM has no cable to pull. What this covers is
# everything either side of it: the migration really does carry an existing
# install across, the recovery unit really is installed and ungated, and the
# guards that stop a user reaching the dark-screen state in the first place
# really do refuse.

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
overrides="$state_dir/display-overrides.json"
rules="$state_dir/toggles/hypr/display-overrides.lua"
legacy_flag="$state_dir/toggles/hypr/internal-monitor-disable.lua"
backup="$(mktemp -d)"

restore_state() {
  rm -f "$overrides" "$rules" "$legacy_flag"
  [[ -f "$backup/display-overrides.json" ]] && cp "$backup/display-overrides.json" "$overrides"
  [[ -f "$backup/display-overrides.lua" ]] && cp "$backup/display-overrides.lua" "$rules"
  [[ -f "$backup/internal-monitor-disable.lua" ]] && cp "$backup/internal-monitor-disable.lua" "$legacy_flag"
  hyprctl reload >/dev/null 2>&1 || true
  rm -rf "$backup"
}
trap restore_state EXIT

[[ -f $overrides ]] && cp "$overrides" "$backup/display-overrides.json"
[[ -f $rules ]] && cp "$rules" "$backup/display-overrides.lua"
[[ -f $legacy_flag ]] && cp "$legacy_flag" "$backup/internal-monitor-disable.lua"

display_name() {
  hyprctl -j monitors | jq -r '[.[] | select(.disabled != true)][0].name'
}

display_scale() {
  hyprctl -j monitors | jq -r --arg name "$1" '[.[] | select(.name == $name)][0].scale'
}

# --- the recovery unit is installed, enabled, and gates on nothing ---

verify_recovery_unit() {
  systemctl --user cat omarchy-recover-internal-monitor.service >/dev/null 2>&1 ||
    fail "the internal display recovery unit is installed"
  pass "the internal display recovery unit is installed"

  # The condition used to name a flag file that display state has moved out of.
  # A condition that silently stops matching disables the rescue without saying
  # so, which is the one failure this whole arrangement exists to prevent.
  ! systemctl --user cat omarchy-recover-internal-monitor.service | grep -F 'ConditionPathExists' >/dev/null ||
    fail "the recovery unit gates on nothing that can go stale"
  pass "the recovery unit gates on nothing that can go stale"

  systemctl --user is-enabled omarchy-recover-internal-monitor.service >/dev/null 2>&1 ||
    fail "the recovery unit is enabled for the session"
  pass "the recovery unit is enabled for the session"

  # Result stays "success" for a unit systemd skipped, so it proves nothing on
  # its own: a stale condition reads exactly like a clean run. ConditionResult
  # is what distinguishes ran from skipped.
  [[ $(systemctl --user show -p ConditionResult --value omarchy-recover-internal-monitor.service) == "yes" ]] ||
    fail "the recovery unit was not skipped this boot" \
      "$(systemctl --user show omarchy-recover-internal-monitor.service | grep -E '^(Condition|Result|ExecMainStatus)')"
  pass "the recovery unit was not skipped this boot"

  [[ $(systemctl --user show -p Result --value omarchy-recover-internal-monitor.service) == "success" ]] ||
    fail "the recovery unit ran cleanly this boot" \
      "$(systemctl --user status omarchy-recover-internal-monitor.service 2>&1 | tail -20)"
  pass "the recovery unit ran cleanly this boot"
}

# --- the rescue runs before the compositor, so it cannot depend on one ---

verify_recovery_command() {
  local command="$OMARCHY_PATH/bin/omarchy-hw-recover-internal-monitor"

  ! grep -F 'hyprctl' "$command" >/dev/null ||
    fail "the rescue reads DRM rather than asking a compositor that is not up yet"
  pass "the rescue reads DRM rather than asking a compositor that is not up yet"

  grep -F '/sys/class/drm/card*-eDP-*/status' "$command" >/dev/null ||
    fail "the rescue finds the internal panel from connector status"
  pass "the rescue finds the internal panel from connector status"

  # It has to clear every location a disable can live in: a machine part-way
  # through the migration must recover the same as one that has finished.
  grep -F 'omarchy-hyprland-monitor-override clear-disabled' "$command" >/dev/null ||
    fail "the rescue clears the display overrides"
  pass "the rescue clears the display overrides"

  grep -F 'internal-monitor-disable.lua' "$OMARCHY_PATH/bin/omarchy-hyprland-monitor-override" >/dev/null ||
    fail "the overrides command still knows the location it replaced"
  pass "the overrides command still knows the location it replaced"

  timeout 10 omarchy-hw-recover-internal-monitor ||
    fail "the rescue runs cleanly with nothing to recover"
  pass "the rescue runs cleanly with nothing to recover"
}

# --- an existing install is carried across ---

verify_migration() {
  local migration="$OMARCHY_PATH/migrations/1786439048.sh"
  local display recorded before

  [[ -f $migration ]] || fail "the display overrides migration ships"

  display="$(display_name)"
  mkdir -p "$(dirname "$legacy_flag")"
  printf 'hl.monitor({ output = "%s", disabled = true })\n' "$display" >"$legacy_flag"

  bash -euo pipefail "$migration" >/dev/null || fail "the migration runs"

  recorded="$(omarchy-hyprland-monitor-override get "$display" disabled)"
  [[ $recorded == "true" ]] || fail "the migration records the display as switched off"
  [[ ! -f $legacy_flag ]] || fail "the migration removes the file it replaces"
  pass "the migration carries a switched-off display into the overrides"

  before="$(cat "$overrides")"
  bash -euo pipefail "$migration" >/dev/null || fail "the migration runs a second time"
  [[ $(cat "$overrides") == "$before" ]] || fail "running the migration twice changes nothing"
  pass "running the migration twice changes nothing"

  # Clear the disable this test just wrote before reloading, or the reload puts
  # the display it was run from out.
  omarchy-hyprland-monitor-override clear "$display"
  hyprctl reload >/dev/null
  wait_until "the display is left on afterwards" 15 \
    bash -c "[[ \$(hyprctl -j monitors | jq -r --arg name '$display' '[.[] | select(.name == \$name)][0].disabled') == false ]]"
}

# --- the guards that keep a user out of the dark-screen state ---

verify_guards() {
  local display
  display="$(display_name)"

  # The focused display and the last lit one are both refused, so the panel
  # cannot produce a machine with nothing on it.
  ! omarchy-hyprland-monitor-toggle "$display" off >/dev/null 2>&1 ||
    fail "switching off the only display is refused"
  pass "switching off the only display is refused"

  [[ $(hyprctl -j monitors | jq -r --arg name "$display" '[.[] | select(.name == $name)][0].disabled') == "false" ]] ||
    fail "the display refused stays on"
  pass "the display refused stays on"

  [[ -z $(omarchy-hyprland-monitor-override get "$display" disabled) ]] ||
    fail "a refused toggle records nothing"
  pass "a refused toggle records nothing"
}

verify_recovery_unit
verify_recovery_command
verify_migration
verify_guards

screenshot "success-display-recovery"
