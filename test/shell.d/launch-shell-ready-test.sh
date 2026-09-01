#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command="$ROOT/bin/omarchy-launch-shell-ready"
[[ -x $command ]] || fail "launch-shell-ready helper is installed"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
hyprctl_count="$tmpdir/hyprctl-count"
mkdir -p "$mock_bin"
: >"$call_log"
printf '0\n' >"$hyprctl_count"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
count=$(<"$HYPRCTL_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$HYPRCTL_COUNT"

if (( count == 1 )); then
  printf '[{"name":"placeholder","disabled":false,"width":0,"height":0}]\n'
else
  printf '[{"name":"DP-1","disabled":false,"width":2560,"height":1440}]\n'
fi
SH

for command_name in omarchy-hyprland-monitor-clamshell omarchy-launch-shell; do
  cat >"$mock_bin/$command_name" <<SH
#!/bin/bash
printf '%s\n' '$command_name' >>"\$CALL_LOG"
SH
done
chmod +x "$mock_bin"/*

CALL_LOG="$call_log" HYPRCTL_COUNT="$hyprctl_count" PATH="$mock_bin:$PATH" \
  OMARCHY_HYPRLAND_READY_ATTEMPTS=3 OMARCHY_HYPRLAND_READY_DELAY=0 \
  "$command"

mapfile -t calls <"$call_log"
(( ${#calls[@]} == 2 )) ||
  fail "helper records display-ready launch calls" "calls: ${calls[*]}"
[[ ${calls[0]} == "omarchy-hyprland-monitor-clamshell" ]] ||
  fail "helper reconciles clamshell state after a real output appears" "calls: ${calls[*]}"
pass "helper reconciles clamshell state after a real output appears"

[[ ${calls[1]} == "omarchy-launch-shell" ]] ||
  fail "helper launches shell after display reconciliation" "calls: ${calls[*]}"
pass "helper launches shell after display reconciliation"

(( $(<"$hyprctl_count") == 2 )) ||
  fail "helper waits past placeholder outputs" "hyprctl calls: $(<"$hyprctl_count")"
pass "helper waits past placeholder outputs"

: >"$call_log"
printf '0\n' >"$hyprctl_count"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
count=$(<"$HYPRCTL_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$HYPRCTL_COUNT"
printf '[{"name":"placeholder","disabled":false,"width":0,"height":0}]\n'
SH
chmod +x "$mock_bin/hyprctl"

CALL_LOG="$call_log" HYPRCTL_COUNT="$hyprctl_count" PATH="$mock_bin:$PATH" \
  OMARCHY_HYPRLAND_READY_ATTEMPTS=3 OMARCHY_HYPRLAND_READY_DELAY=0 \
  "$command"

mapfile -t calls <"$call_log"
(( ${#calls[@]} == 2 )) ||
  fail "helper records fallback launch calls" "calls: ${calls[*]}"
[[ ${calls[0]} == "omarchy-hyprland-monitor-clamshell" ]] ||
  fail "helper reconciles clamshell state before fallback launch" "calls: ${calls[*]}"
pass "helper reconciles clamshell state before fallback launch"

[[ ${calls[1]} == "omarchy-launch-shell" ]] ||
  fail "helper falls back to launching shell after bounded attempts" "calls: ${calls[*]}"
pass "helper falls back to launching shell after bounded attempts"

(( $(<"$hyprctl_count") == 3 )) ||
  fail "helper bounds output readiness checks" "hyprctl calls: $(<"$hyprctl_count")"
pass "helper bounds output readiness checks"

autostart="$ROOT/default/hypr/autostart.lua"
ready_line=$(grep -n 'hl\.exec_cmd("omarchy-launch-shell-ready")' "$autostart" | cut -d: -f1 || true)
direct_shell_line=$(grep -n 'hl\.exec_cmd("omarchy-launch-shell")' "$autostart" | cut -d: -f1 || true)

[[ -n $ready_line ]] || fail "autostart launches shell through the display-ready helper"
pass "autostart launches shell through the display-ready helper"

[[ -z $direct_shell_line ]] ||
  fail "autostart does not also launch the shell directly"
pass "autostart does not also launch the shell directly"
