#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

monitor_watch="$ROOT/bin/omarchy-hyprland-monitor-watch"
sleep_lock="$ROOT/bin/omarchy-system-sleep-lock"
system_wake="$ROOT/bin/omarchy-system-wake"
clamshell="$ROOT/bin/omarchy-hyprland-monitor-clamshell"
lock_service="$ROOT/shell/plugins/lock/Service.qml"
hw_clamshell="$ROOT/bin/omarchy-hw-clamshell"

grep -F 'recover_after_monitor_removal' "$monitor_watch" >/dev/null
grep -F 'sleep 1' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-clamshell' "$monitor_watch" >/dev/null
pass "monitor watcher retries internal monitor recovery after removal"

grep -F 'monitoradded\>\>*|monitoraddedv2\>\>*)' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-clamshell' "$monitor_watch" >/dev/null
pass "monitor watcher disables the internal monitor after closed-lid external hotplug"

grep -F '/proc/acpi/button/lid/*/state' "$hw_clamshell" >/dev/null
grep -F 'omarchy-hw-external-monitors' "$hw_clamshell" >/dev/null
pass "clamshell helper detects closed-lid external monitor state"

grep -F 'omarchy-hyprland-monitor-internal recover >/dev/null 2>&1 || true' "$clamshell" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal-mirror recover >/dev/null 2>&1 || true' "$clamshell" >/dev/null
grep -F 'omarchy-hw-clamshell' "$clamshell" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal off >/dev/null 2>&1 || true' "$clamshell" >/dev/null
pass "clamshell monitor sync recovers stale toggles and disables internal display"

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
