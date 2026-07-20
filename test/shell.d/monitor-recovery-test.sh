#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

monitor_watch="$ROOT/bin/omarchy-hyprland-monitor-watch"
monitor_internal="$ROOT/bin/omarchy-hyprland-monitor-internal"
monitor_mirror="$ROOT/bin/omarchy-hyprland-monitor-internal-mirror"
monitor_external_active="$ROOT/bin/omarchy-hyprland-monitor-external-active"
sleep_lock="$ROOT/bin/omarchy-system-sleep-lock"
system_wake="$ROOT/bin/omarchy-system-wake"
clamshell="$ROOT/bin/omarchy-hyprland-monitor-clamshell"
lock_service="$ROOT/shell/plugins/lock/Service.qml"
hw_clamshell="$ROOT/bin/omarchy-hw-clamshell"
utilities="$ROOT/default/hypr/bindings/utilities.lua"

grep -F 'sleep "$delay"' "$monitor_watch" >/dev/null
grep -F 'for delay in 1 3 7; do' "$monitor_watch" >/dev/null
grep -F 'poll_clamshell_state &' "$monitor_watch" >/dev/null
grep -F 'flock -n 9' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-clamshell' "$monitor_watch" >/dev/null
pass "monitor watcher retries internal monitor recovery after removal"

grep -F 'monitoradded\>\>*|monitoraddedv2\>\>*)' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-clamshell' "$monitor_watch" >/dev/null
pass "monitor watcher disables the internal monitor after closed-lid external hotplug"

grep -F 'sync_clamshell_after_monitor_change' "$monitor_watch" >/dev/null
grep -F 'socat -U - "UNIX-CONNECT:$SOCKET"' "$monitor_watch" >/dev/null
pass "monitor watcher reconciles clamshell state on startup"

grep -F '/proc/acpi/button/lid/*/state' "$hw_clamshell" >/dev/null
grep -F 'omarchy-hw-external-monitors' "$hw_clamshell" >/dev/null
pass "clamshell helper detects closed-lid external monitor state"

grep -F 'hyprctl monitors -j' "$monitor_external_active" >/dev/null
grep -F 'select(.name | test("^(eDP|LVDS|DSI)-") | not)' "$monitor_external_active" >/dev/null
grep -F 'select(.disabled == false)' "$monitor_external_active" >/dev/null
pass "active external monitor helper checks Hyprland outputs"

grep -F 'omarchy-hyprland-monitor-internal recover >/dev/null 2>&1 || true' "$clamshell" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal-mirror recover >/dev/null 2>&1 || true' "$clamshell" >/dev/null
grep -F 'internal-monitor-clamshell.lua' "$clamshell" >/dev/null
grep -F 'disabled = true' "$clamshell" >/dev/null
grep -F 'MANUAL_DISABLE_FLAG' "$clamshell" >/dev/null
! grep -F 'rm -f "$MANUAL_DISABLE_FLAG"' "$clamshell" >/dev/null
! grep -F '>"$MANUAL_DISABLE_FLAG"' "$clamshell" >/dev/null
grep -F 'read_monitor_scale' "$clamshell" >/dev/null
grep -F 'scale = $scale' "$clamshell" >/dev/null
grep -F 'hyprctl dispatch "hl.dsp.dpms({ action = \"$action\", monitor = \"$INTERNAL\" })"' "$clamshell" >/dev/null
grep -F 'hyprctl monitors all -j' "$clamshell" >/dev/null
grep -F 'omarchy-hyprland-monitor-external-active' "$clamshell" >/dev/null
grep -F 'omarchy-hw-clamshell' "$clamshell" >/dev/null
pass "clamshell monitor sync disables laptop output and force-recovers it"

grep -F "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })' >/dev/null 2>&1 || true" "$monitor_internal" >/dev/null
grep -F 'hyprctl monitors all -j' "$monitor_internal" >/dev/null
grep -F 'omarchy-hyprland-monitor-external-active' "$monitor_internal" >/dev/null
grep -F 'wake' "$monitor_internal" >/dev/null
grep -F 'omarchy-hyprland-toggle-enabled $TOGGLE || return 0' "$monitor_internal" >/dev/null
pass "internal monitor helper can re-enable disabled laptop displays"
pass "internal monitor recovery only wakes displays when it re-enables one"

grep -F 'omarchy-hyprland-monitor-external-active' "$monitor_mirror" >/dev/null
pass "internal mirror helper recovers when no active external display remains"

grep -F 'switch:on:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell"' "$utilities" >/dev/null
grep -F 'switch:off:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell"' "$utilities" >/dev/null
pass "lid switch bindings reconcile clamshell display state"

grep -F 'omarchy-hyprland-monitor-clamshell >/dev/null 2>&1 || true' "$sleep_lock" >/dev/null
grep -F '(( attempt % 5 == 0 )) && sync_clamshell' "$sleep_lock" >/dev/null
pass "sleep lock syncs clamshell display state while waiting for secure lock"

grep -F 'omarchy-hyprland-monitor-clamshell >/dev/null 2>&1 || true' "$system_wake" >/dev/null
pass "system wake resyncs clamshell display state"

grep -F 'lock-pending: no-real-screen' "$lock_service" >/dev/null
grep -F 'lock-pending: screen-stabilizing' "$lock_service" >/dev/null
grep -F 'id: sessionLockStabilizeTimer' "$lock_service" >/dev/null
grep -F 'function onScreensChanged() { root.requestSessionLock() }' "$lock_service" >/dev/null
grep -F 'realScreens: root.realScreenCount()' "$lock_service" >/dev/null
pass "lock service waits for stable real screens before session lock"
