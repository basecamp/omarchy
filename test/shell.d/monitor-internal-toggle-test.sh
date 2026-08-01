#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
toggles_dir="$home_dir/.local/state/omarchy/toggles/hypr"
disable_flag="$toggles_dir/internal-monitor-disable.lua"
mirror_flag="$toggles_dir/internal-monitor-mirror.lua"
hyprctl_log="$test_tmp/hyprctl.log"
notification_log="$test_tmp/notification.log"

mkdir -p "$stub_bin" "$toggles_dir"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_HYPRCTL_LOG"
SH

cat >"$stub_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
printf 'eDP-1\n'
SH

cat >"$stub_bin/omarchy-hyprland-monitor-external-active" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_EXTERNAL_ACTIVE:-true} == "true" ]]
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_NOTIFICATION_LOG"
SH

chmod +x "$stub_bin"/*

run_internal() {
  : >"$hyprctl_log"
  : >"$notification_log"

  HOME="$home_dir" \
    OMARCHY_PATH="$ROOT" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_LOG="$hyprctl_log" \
    OMARCHY_TEST_NOTIFICATION_LOG="$notification_log" \
    OMARCHY_TEST_EXTERNAL_ACTIVE="${OMARCHY_TEST_EXTERNAL_ACTIVE:-true}" \
    "$ROOT/bin/omarchy-hyprland-monitor-internal" "$1"
}

rm -f "$disable_flag" "$mirror_flag"
run_internal off
grep -F 'disabled = true' "$disable_flag" >/dev/null ||
  fail "internal monitor disable writes the Hyprland rule" "$(cat "$disable_flag" 2>&1)"
grep -F 'reload' "$hyprctl_log" >/dev/null || fail "internal monitor disable reloads Hyprland"
pass "internal monitor disable writes the Hyprland rule"

# Mirroring drives the internal output as well. Before, the disable path bailed
# out silently whenever the mirror toggle was up, so Super + Ctrl + Delete did
# nothing at all until the user left mirrored mode first.
rm -f "$disable_flag"
printf 'hl.monitor({ output = "DP-1", mirror = "eDP-1" })\n' >"$mirror_flag"
run_internal off
[[ ! -f $mirror_flag ]] || fail "internal monitor disable clears mirroring first"
grep -F 'disabled = true' "$disable_flag" >/dev/null ||
  fail "internal monitor disable works while mirroring is on" "$(cat "$disable_flag" 2>&1)"
grep -F 'Laptop display disabled' "$notification_log" >/dev/null ||
  fail "internal monitor disable reports back while mirroring is on" "$(cat "$notification_log")"
pass "internal monitor disable clears mirroring first"
pass "internal monitor disable works while mirroring is on"

run_internal on
[[ ! -f $disable_flag ]] || fail "internal monitor enable clears the disable rule"
pass "internal monitor enable clears the disable rule"

rm -f "$disable_flag" "$mirror_flag"
OMARCHY_TEST_EXTERNAL_ACTIVE=false run_internal off && status=0 || status=$?
(( status == 1 )) || fail "internal monitor disable refuses to kill the only display" "exit: $status"
[[ ! -f $disable_flag ]] || fail "internal monitor disable writes no rule without an external display"
pass "internal monitor disable refuses to kill the only display"
