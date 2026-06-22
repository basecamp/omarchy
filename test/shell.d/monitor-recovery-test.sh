#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

monitor_watch="$ROOT/bin/omarchy-hyprland-monitor-watch"
sleep_lock="$ROOT/bin/omarchy-system-sleep-lock"
lock_service="$ROOT/shell/plugins/lock/Service.qml"

grep -F 'recover_after_monitor_removal' "$monitor_watch" >/dev/null
grep -F 'sleep 1' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal recover' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal-mirror recover' "$monitor_watch" >/dev/null
pass "monitor watcher retries internal monitor recovery after removal"

grep -F 'omarchy-hyprland-monitor-internal recover >/dev/null 2>&1 || true' "$sleep_lock" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal-mirror recover >/dev/null 2>&1 || true' "$sleep_lock" >/dev/null
grep -F '(( attempt % 5 == 0 )) && recover_internal_monitor_toggles' "$sleep_lock" >/dev/null
pass "sleep lock recovers internal monitor toggles while waiting for secure lock"

grep -F 'lock-pending: no-real-screen' "$lock_service" >/dev/null
grep -F 'function onScreensChanged() { root.requestSessionLock() }' "$lock_service" >/dev/null
grep -F 'realScreens: root.realScreenCount()' "$lock_service" >/dev/null
pass "lock service defers session lock until a real screen exists"
