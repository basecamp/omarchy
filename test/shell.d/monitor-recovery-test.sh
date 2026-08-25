#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

monitor_watch="$ROOT/bin/omarchy-hyprland-monitor-watch"
monitor_internal="$ROOT/bin/omarchy-hyprland-monitor-internal"
monitor_mirror="$ROOT/bin/omarchy-hyprland-monitor-internal-mirror"
monitor_laptop="$ROOT/bin/omarchy-hyprland-monitor-laptop"
monitor_external_active="$ROOT/bin/omarchy-hyprland-monitor-external-active"
system_wake="$ROOT/bin/omarchy-system-wake"
clamshell="$ROOT/bin/omarchy-hyprland-monitor-clamshell"
lock_service="$ROOT/shell/plugins/lock/Service.qml"
hw_clamshell="$ROOT/bin/omarchy-hw-clamshell"
hw_laptop_closed="$ROOT/bin/omarchy-hw-laptop-closed"
utilities="$ROOT/default/hypr/bindings/utilities.lua"

grep -F 'sleep "$delay"' "$monitor_watch" >/dev/null || fail "monitor watcher waits between recovery attempts"
grep -F 'for delay in 1 3 7; do' "$monitor_watch" >/dev/null || fail "monitor watcher retries recovery on a 1/3/7 second ladder"
grep -F 'poll_clamshell_state &' "$monitor_watch" >/dev/null || fail "monitor watcher polls clamshell state in the background"
grep -F 'flock -n 9' "$monitor_watch" >/dev/null || fail "monitor watcher locks so one recovery loop runs at a time"
grep -F 'omarchy-hyprland-monitor-clamshell' "$monitor_watch" >/dev/null || fail "monitor watcher calls the clamshell sync helper"
pass "monitor watcher retries internal monitor recovery after removal"

grep -F 'monitoradded\>\>*|monitoraddedv2\>\>*)' "$monitor_watch" >/dev/null || fail "monitor watcher reacts to monitoradded and monitoraddedv2"
grep -F 'omarchy-hyprland-monitor-clamshell' "$monitor_watch" >/dev/null || fail "monitor watcher syncs clamshell state on a monitor hotplug"
pass "monitor watcher disables the internal monitor after closed-lid external hotplug"

grep -F 'sync_clamshell_after_monitor_change' "$monitor_watch" >/dev/null || fail "monitor watcher reconciles clamshell state after a monitor change"
grep -F 'socat -U - "UNIX-CONNECT:$SOCKET"' "$monitor_watch" >/dev/null || fail "monitor watcher reads the Hyprland event socket"
pass "monitor watcher reconciles clamshell state on startup"

grep -F 'omarchy-hw-laptop && omarchy-hyprland-monitor-external-active' "$monitor_watch" >/dev/null || fail "clamshell poll starts only on a docked laptop"
grep -F 'sync_poll_state' "$monitor_watch" >/dev/null || fail "monitor watcher tracks whether the clamshell poll should run"
grep -F 'done < <(socat' "$monitor_watch" >/dev/null || fail "monitor watcher reads events without losing state to a subshell"
pass "clamshell poll only runs on a docked laptop, not desktops or undocked laptops"

# Recovery costs a reload per attempt, so it must not run on a healthy machine,
# and only one loop may run across the events that start it.
grep -F '(( state == 1 )) && break' "$monitor_watch" >/dev/null || fail "modeless recovery stops once a monitor reports a mode"
grep -F 'delay = delay * 2 > 60 ? 60 : delay * 2' "$monitor_watch" >/dev/null || fail "modeless recovery backs off and caps the delay at 60 seconds"
grep -F '9>"$MODELESS_LOCK"' "$monitor_watch" >/dev/null || fail "modeless recovery takes its own lock file"
grep -F 'flock -w 1 9 || exit 0' "$monitor_watch" >/dev/null || fail "a second modeless recovery loop exits instead of stacking"
pass "modeless monitor recovery runs one backing-off loop while a monitor has no mode"

# Nothing fires an event for this state, so an unanswered query must not end
# recovery -- but a compositor that never answers has gone with the session.
grep -F '(( state == 2 )) && (( ++unanswered > 20 )) && break' "$monitor_watch" >/dev/null || fail "modeless recovery gives up after 20 unanswered queries"
pass "modeless recovery retries unanswered queries without waiting on a dead compositor"

grep -F 'configreloaded\>\>*)' "$monitor_watch" >/dev/null || fail "modeless recovery also runs after a config reload"
pass "modeless recovery also runs after a config reload"

grep -F 'omarchy-hyprland-reload-guard paused' "$monitor_watch" >/dev/null || fail "modeless recovery does not reload into a package transaction"
pass "modeless recovery does not reload into a package transaction"

grep -F '.disabled != true and (.width == 0 or .height == 0)' "$ROOT/bin/omarchy-hyprland-monitor-modeless" >/dev/null || fail "modeless helper ignores monitors disabled on purpose"
grep -F 'hyprctl monitors all -j' "$ROOT/bin/omarchy-hyprland-monitor-modeless" >/dev/null || fail "modeless helper asks for all monitors so mirrors stay visible"
pass "modeless helper sees mirrors and ignores monitors disabled on purpose"

grep -F 'omarchy-hw-laptop-closed && omarchy-hw-external-monitors' "$hw_clamshell" >/dev/null || fail "clamshell helper needs both a closed lid and an external monitor"
grep -F '/proc/acpi/button/lid/*/state' "$hw_laptop_closed" >/dev/null || fail "laptop-closed helper reads the ACPI lid state"
pass "clamshell helper detects closed-lid external monitor state"

# A mirrored external is absent from plain `monitors`, so asking without `all`
# reads as a disconnect and hands the mirror toggle straight to recovery.
grep -F 'hyprctl monitors all -j' "$monitor_external_active" >/dev/null || fail "active external helper asks for all monitors so mirrors stay visible"
grep -F 'select(.name | test("^(eDP|LVDS|DSI)-") | not)' "$monitor_external_active" >/dev/null || fail "active external helper skips internal panels"
grep -F 'select(.disabled == false)' "$monitor_external_active" >/dev/null || fail "active external helper ignores disabled monitors"
pass "active external monitor helper sees mirrors and ignores monitors disabled on purpose"

grep -F 'omarchy-hyprland-monitor-internal recover >/dev/null 2>&1 || true' "$clamshell" >/dev/null || fail "clamshell sync force-recovers the internal monitor"
grep -F 'omarchy-hyprland-monitor-internal-mirror recover >/dev/null 2>&1 || true' "$clamshell" >/dev/null || fail "clamshell sync force-recovers the internal mirror"
grep -F 'internal-monitor-clamshell.lua' "$clamshell" >/dev/null || fail "clamshell sync writes internal-monitor-clamshell.lua"
grep -F 'disabled = true' "$clamshell" >/dev/null || fail "clamshell sync disables the internal monitor"
grep -F 'MANUAL_DISABLE_FLAG' "$clamshell" >/dev/null || fail "clamshell sync reads the manual disable flag"
! grep -F 'rm -f "$MANUAL_DISABLE_FLAG"' "$clamshell" >/dev/null || fail "clamshell sync never clears the manual disable flag"
! grep -F '>"$MANUAL_DISABLE_FLAG"' "$clamshell" >/dev/null || fail "clamshell sync never writes the manual disable flag"
grep -F 'read_monitor_scale' "$clamshell" >/dev/null || fail "clamshell sync reads the configured monitor scale"
grep -F 'scale = $scale' "$clamshell" >/dev/null || fail "clamshell sync keeps the monitor scale when it rewrites the config"
grep -F 'hyprctl dispatch "hl.dsp.dpms({ action = \"$action\", monitor = \"$INTERNAL\" })"' "$clamshell" >/dev/null || fail "clamshell sync drives DPMS on the internal monitor"
grep -F 'hyprctl monitors all -j' "$clamshell" >/dev/null || fail "clamshell sync asks for all monitors so mirrors stay visible"
grep -F 'omarchy-hyprland-monitor-external-active' "$clamshell" >/dev/null || fail "clamshell sync checks for an active external monitor"
grep -F 'omarchy-hw-clamshell' "$clamshell" >/dev/null || fail "clamshell sync checks the clamshell hardware state"
pass "clamshell monitor sync disables laptop output and force-recovers it"

grep -F "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })' >/dev/null 2>&1 || true" "$monitor_internal" >/dev/null || fail "internal monitor recovery re-enables DPMS"
grep -F 'omarchy-hyprland-monitor-laptop' "$monitor_internal" >/dev/null || fail "internal monitor helper resolves the laptop output"
grep -F 'hyprctl monitors all -j' "$monitor_laptop" >/dev/null || fail "laptop helper asks for all monitors so mirrors stay visible"
grep -F 'omarchy-hyprland-monitor-external-active' "$monitor_internal" >/dev/null || fail "internal monitor helper checks for an active external monitor"
grep -F 'wake' "$monitor_internal" >/dev/null || fail "internal monitor helper supports the wake action"
grep -F 'omarchy-hyprland-toggle-enabled $TOGGLE || return 0' "$monitor_internal" >/dev/null || fail "internal monitor recovery only wakes displays when it re-enabled one"
pass "internal monitor helper can re-enable disabled laptop displays"
pass "internal monitor recovery only wakes displays when it re-enables one"

grep -F 'omarchy-hyprland-monitor-external-active' "$monitor_mirror" >/dev/null || fail "internal mirror helper checks for an active external monitor"
pass "internal mirror helper recovers when no active external display remains"

grep -F 'switch:on:Lid Switch", nil, "omarchy-system-lid-close"' "$utilities" >/dev/null || fail "lid close binding locks the session"
grep -F 'switch:off:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell"' "$utilities" >/dev/null || fail "lid open binding reconciles clamshell display state"
pass "lid switch bindings lock on close and reconcile clamshell display state"

grep -F 'omarchy-hyprland-monitor-clamshell >/dev/null 2>&1 || true' "$system_wake" >/dev/null || fail "system wake resyncs clamshell display state"
pass "system wake resyncs clamshell display state"

grep -F 'lock-pending: no-real-screen' "$lock_service" >/dev/null || fail "lock service reports a pending lock with no real screen"
grep -F 'lock-pending: screen-stabilizing' "$lock_service" >/dev/null || fail "lock service reports a pending lock while screens stabilize"
grep -F 'id: sessionLockStabilizeTimer' "$lock_service" >/dev/null || fail "lock service has a screen stabilize timer"
grep -Pzo 'function onScreensChanged\(\) \{\n(.*\n)*?\s*root\.requestSessionLock\(\)\n' "$lock_service" >/dev/null || fail "a screen change requests the session lock"
grep -F 'realScreens: root.realScreenCount()' "$lock_service" >/dev/null || fail "lock service counts real screens"
pass "lock service waits for stable real screens before session lock"
