#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
toggle_dir="$home_dir/.local/state/omarchy/toggles/hypr"
hyprctl_log="$test_tmp/hyprctl.log"
internal_log="$test_tmp/internal.log"
override_log="$test_tmp/override.log"

mkdir -p "$stub_bin" "$toggle_dir"

# eDP-1 is the internal display, DP-1 external. OMARCHY_TEST_FOCUS names the
# focused display in the `monitors all` fixture; OMARCHY_TEST_FOCUS_DRIFT names
# whoever plain `monitors` reports afterwards, standing in for Hyprland stealing
# focus onto a display it has just lit.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

focused="${OMARCHY_TEST_FOCUS:-eDP-1}"

focus_flag() {
  [[ $1 == "$focused" ]] && printf 'true' || printf 'false'
}

if [[ $1 == "monitors" && $2 == "all" && $3 == "-j" ]]; then
  case ${OMARCHY_TEST_MONITORS:-both} in
    both)
      printf '[{"name":"eDP-1","disabled":false,"focused":%s},{"name":"DP-1","disabled":false,"focused":%s}]' \
        "$(focus_flag eDP-1)" "$(focus_flag DP-1)"
      ;;
    external-off)
      printf '[{"name":"eDP-1","disabled":false,"focused":%s},{"name":"DP-1","disabled":true,"focused":false}]' \
        "$(focus_flag eDP-1)"
      ;;
    lone-external)
      printf '[{"name":"DP-1","disabled":false,"focused":%s}]' "$(focus_flag DP-1)"
      ;;
  esac
elif [[ $1 == "monitors" && $2 == "-j" ]]; then
  printf '[{"name":"%s","focused":true}]' "${OMARCHY_TEST_FOCUS_DRIFT:-$focused}"
elif [[ $1 == "reload" ]]; then
  printf 'reload\n' >>"$OMARCHY_TEST_HYPRCTL_LOG"
elif [[ $1 == "dispatch" ]]; then
  printf 'dispatch %s\n' "$2" >>"$OMARCHY_TEST_HYPRCTL_LOG"
else
  exit 1
fi
SH

cat >"$stub_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_MONITORS:-both} == "lone-external" ]] && exit 0
printf 'eDP-1\n'
SH

cat >"$stub_bin/omarchy-hyprland-monitor-internal" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >>"$OMARCHY_TEST_INTERNAL_LOG"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

# Disable state lives in the overrides file. The stub records what was asked of
# it and answers from a fixture, so these tests stay about the toggle's own
# decisions rather than the overrides command's storage.
cat >"$stub_bin/omarchy-hyprland-monitor-override" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_OVERRIDE_LOG"
case "$1" in
  is-disabled) [[ ${OMARCHY_TEST_OVERRIDE_DISABLED:-false} == "true" ]] ;;
  *) exit 0 ;;
esac
SH

chmod +x "$stub_bin"/*

run_toggle() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_LOG="$hyprctl_log" \
    OMARCHY_TEST_INTERNAL_LOG="$internal_log" \
    OMARCHY_TEST_OVERRIDE_LOG="$override_log" \
    OMARCHY_TEST_OVERRIDE_DISABLED="${OMARCHY_TEST_OVERRIDE_DISABLED:-false}" \
    OMARCHY_TEST_MONITORS="${OMARCHY_TEST_MONITORS:-both}" \
    OMARCHY_TEST_FOCUS="${OMARCHY_TEST_FOCUS:-eDP-1}" \
    OMARCHY_TEST_FOCUS_DRIFT="${OMARCHY_TEST_FOCUS_DRIFT:-}" \
    "$ROOT/bin/omarchy-hyprland-monitor-toggle" "$@"
}

reset_state() {
  rm -f "$toggle_dir"/*.lua
  : >"$hyprctl_log"
  : >"$internal_log"
  : >"$override_log"
}

# --- disabling an external display persists and reloads ---

reset_state
run_toggle DP-1 off
grep -Fx 'set DP-1 disabled true' "$override_log" >/dev/null || fail "disabling a display records it"
grep -F 'reload' "$hyprctl_log" >/dev/null || fail "disabling a display reloads Hyprland"
pass "disabling an external display persists and reloads"

# --- the focused display can never be disabled ---

reset_state
OMARCHY_TEST_FOCUS=DP-1 run_toggle DP-1 off && fail "disabling the focused display exits non-zero"
[[ ! -s $override_log ]] || fail "disabling the focused display records nothing"
[[ ! -s $hyprctl_log ]] || fail "disabling the focused display does not reload"
pass "the focused display can never be disabled"

# --- the focused internal display is refused before delegating ---

reset_state
OMARCHY_TEST_FOCUS=eDP-1 run_toggle eDP-1 off && fail "disabling the focused internal display exits non-zero"
[[ ! -s $internal_log ]] || fail "the focused internal display never reaches the laptop-display command"
pass "the focused internal display is refused before delegating"

# --- enabling clears the flag and reloads ---

reset_state
OMARCHY_TEST_MONITORS=external-off OMARCHY_TEST_FOCUS_DRIFT=DP-1 run_toggle DP-1 on
grep -Fx 'clear-disabled DP-1' "$override_log" >/dev/null || fail "enabling a display clears the record"
grep -F 'reload' "$hyprctl_log" >/dev/null || fail "enabling a display reloads Hyprland"
pass "enabling an external display clears the flag and reloads"

# --- enabling puts focus back where it was ---

reset_state
OMARCHY_TEST_MONITORS=external-off OMARCHY_TEST_FOCUS_DRIFT=DP-1 run_toggle DP-1 on
grep -F 'hl.dsp.focus({ monitor = "eDP-1" })' "$hyprctl_log" >/dev/null ||
  fail "enabling a display restores focus to the display that had it"
pass "enabling puts focus back where it was"

# --- focus is left alone when Hyprland does not steal it ---

reset_state
run_toggle DP-1 off
! grep -F 'hl.dsp.focus' "$hyprctl_log" >/dev/null || fail "focus is not redispatched when it never moved"
pass "focus is left alone when Hyprland does not steal it"

# --- enabling an already-enabled display is a no-op ---

reset_state
run_toggle DP-1 on
[[ ! -s $hyprctl_log ]] || fail "enabling an already-enabled display skips the reload"
pass "enabling an already-enabled display is a no-op"

# --- the last enabled display is protected ---

reset_state
OMARCHY_TEST_MONITORS=lone-external OMARCHY_TEST_FOCUS=none run_toggle DP-1 off &&
  fail "disabling the only active display exits non-zero"
! grep -Fx 'set DP-1 disabled true' "$override_log" >/dev/null || fail "disabling the only active display records nothing"
[[ ! -s $hyprctl_log ]] || fail "disabling the only active display does not reload"
pass "the last enabled display is protected"

# --- toggle picks its direction from current state ---

reset_state
run_toggle DP-1
grep -Fx 'set DP-1 disabled true' "$override_log" >/dev/null || fail "toggle disables an enabled display"
: >"$override_log"
OMARCHY_TEST_MONITORS=external-off OMARCHY_TEST_FOCUS_DRIFT=DP-1 run_toggle DP-1
grep -Fx 'clear-disabled DP-1' "$override_log" >/dev/null || fail "toggle enables a disabled display"
pass "toggle picks its direction from current state"

# --- a runtime-disabled display gets its state persisted ---

reset_state
OMARCHY_TEST_MONITORS=external-off run_toggle DP-1 off
grep -Fx 'set DP-1 disabled true' "$override_log" >/dev/null || fail "disabling an already-dark display persists the state"
[[ ! -s $hyprctl_log ]] || fail "disabling an already-dark display skips the reload"
pass "a runtime-disabled display gets its state persisted"

# --- the internal display delegates to the laptop-display command ---

reset_state
OMARCHY_TEST_FOCUS=DP-1 run_toggle eDP-1 off
[[ $(<"$internal_log") == "off" ]] || fail "the internal display delegates to omarchy-hyprland-monitor-internal"
! grep -Fx 'set eDP-1 disabled true' "$override_log" >/dev/null || fail "the internal display is left to its own command"
pass "the internal display delegates to the laptop-display command"

# --- input validation ---

reset_state
run_toggle DP-9 off && fail "an unknown output exits non-zero"
run_toggle "../escape" off && fail "an output name with path separators is rejected"
run_toggle DP-1 sideways && fail "an unknown action exits non-zero"
run_toggle && fail "a missing output name exits non-zero"
[[ ! -s $hyprctl_log ]] || fail "rejected input does not reload"
pass "input validation rejects bad output names and actions"
