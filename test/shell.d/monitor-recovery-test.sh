#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

monitor_watch="$ROOT/bin/omarchy-hyprland-monitor-watch"
sleep_lock="$ROOT/bin/omarchy-system-sleep-lock"

grep -F 'recover_after_monitor_removal' "$monitor_watch" >/dev/null
grep -F 'sleep 1' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal recover' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal-mirror recover' "$monitor_watch" >/dev/null
pass "monitor watcher retries internal monitor recovery after removal"

grep -F 'omarchy-hyprland-monitor-internal recover >/dev/null 2>&1 || true' "$sleep_lock" >/dev/null
grep -F 'omarchy-hyprland-monitor-internal-mirror recover >/dev/null 2>&1 || true' "$sleep_lock" >/dev/null
pass "sleep lock recovers internal monitor toggles before suspend"
