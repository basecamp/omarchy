#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

battery_service="$ROOT/shell/plugins/services/battery/Service.qml"

# The model decides whether to dismiss; these cover the service acting on that
# decision, which the model tests below cannot reach.
grep -F 'else if (state.dismiss) dismissLowBatteryWarning()' "$battery_service" >/dev/null ||
  fail "battery service dismisses the warning by its own summary"
grep -F 'dismissProcess.command = ["omarchy-notification-dismiss", lowBatterySummary]' "$battery_service" >/dev/null ||
  fail "battery service dismisses the warning by its own summary"
grep -F 'readonly property string lowBatterySummary: "Time to recharge!"' "$battery_service" >/dev/null ||
  fail "battery service dismisses the warning by its own summary"
pass "battery service dismisses the warning by its own summary"

# Both commands are spawned, and the dismiss takes down every toast whose
# summary contains the headline, so the two must never overlap. checkBattery
# latches notifiedLowBattery before either runs and computes both decisions
# from that latch, so whatever is dropped here is never recomputed by a later
# poll: a dismiss that races ahead of its warning strands a toast that never
# expires, and a warning posted under a running dismiss is swept away with the
# toast that dismiss was sent for, leaving the user low with nothing on screen.
grep -A9 -F 'function dismissLowBatteryWarning() {' "$battery_service" |
  grep -F 'if (warningProcess.running || dismissProcess.running) {' >/dev/null ||
  fail "battery service holds a dismiss while either process is in flight"
grep -A9 -F 'function dismissLowBatteryWarning() {' "$battery_service" |
  grep -F 'pendingDismiss = true' >/dev/null ||
  fail "battery service holds a dismiss while either process is in flight"
pass "battery service holds a dismiss while either process is in flight"

grep -A10 -F 'function sendLowBatteryWarning(level) {' "$battery_service" |
  grep -F 'if (dismissProcess.running) {' >/dev/null ||
  fail "battery service holds a warning while a dismiss is in flight"
grep -A10 -F 'function sendLowBatteryWarning(level) {' "$battery_service" |
  grep -F 'pendingWarningLevel = level' >/dev/null ||
  fail "battery service holds a warning while a dismiss is in flight"
pass "battery service holds a warning while a dismiss is in flight"

# The held request may only clear on the path that actually issues the command,
# and each function has to drop the other's: charging again retracts a held
# warning, and unplugging again retracts a held dismiss.
grep -A9 -F 'function dismissLowBatteryWarning() {' "$battery_service" |
  grep -A1 -F 'pendingDismiss = false' | grep -F 'dismissProcess.command' >/dev/null ||
  fail "battery service clears the held dismiss only when it issues one"
grep -A10 -F 'function sendLowBatteryWarning(level) {' "$battery_service" |
  grep -A3 -F 'pendingWarningLevel = -1' | grep -F 'warningProcess.command' >/dev/null ||
  fail "battery service clears the held warning only when it issues one"
pass "battery service clears a held request only when it issues one"

grep -A2 -F 'function dismissLowBatteryWarning() {' "$battery_service" |
  grep -F 'pendingWarningLevel = -1' >/dev/null ||
  fail "battery service retracts a held warning when the battery starts charging"
grep -A2 -F 'function sendLowBatteryWarning(level) {' "$battery_service" |
  grep -F 'pendingDismiss = false' >/dev/null ||
  fail "battery service retracts a held dismiss when a fresh warning supersedes it"
pass "battery service retracts the request the other decision supersedes"

# A second warning while one is already going out would only duplicate the
# toast, so that one is dropped rather than held.
grep -A10 -F 'function sendLowBatteryWarning(level) {' "$battery_service" |
  grep -F 'if (warningProcess.running) return' >/dev/null ||
  fail "battery service drops a duplicate warning while one is already going out"
pass "battery service drops a duplicate warning while one is already going out"

# Whichever process was in flight has to replay what was held behind it, or the
# request is lost for good.
(( $(grep -c 'onExited: root.runPendingBatteryNotification()' "$battery_service") == 2 )) ||
  fail "both the warning and the dismiss replay a held request when they exit"
grep -A3 -F 'function runPendingBatteryNotification() {' "$battery_service" |
  grep -F 'if (pendingDismiss) dismissLowBatteryWarning()' >/dev/null ||
  fail "the replay issues a held dismiss"
grep -A3 -F 'function runPendingBatteryNotification() {' "$battery_service" |
  grep -F 'else if (pendingWarningLevel >= 0) sendLowBatteryWarning(pendingWarningLevel)' >/dev/null ||
  fail "the replay issues a held warning"
pass "both the warning and the dismiss replay a held request when they exit"

# The summary the service dismisses has to be the headline the command sends.
grep -F '"Time to recharge!"' "$ROOT/bin/omarchy-battery-low" >/dev/null ||
  fail "battery warning headline matches the summary the service dismisses"
pass "battery warning headline matches the summary the service dismisses"

run_node_test <<'JS'
const battery = requireFromRoot('shell/plugins/services/battery/BatteryModel.js')
const discharging = 1

assertEqual(battery.batteryPercentage({ isPresent: true, percentage: 0.126 }), 13, 'battery rounds display percentage')
assertEqual(battery.batteryPercentage({ isPresent: false, percentage: 0.5 }), -1, 'battery reports missing battery')
assert(battery.isDischarging({ isPresent: true, state: discharging }, true, discharging), 'battery detects discharging state')
assert(!battery.isDischarging({ isPresent: true, state: discharging }, false, discharging), 'battery requires on-battery state')

assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, false),
  { level: 8, notify: true, dismiss: false, notifiedLowBattery: true },
  'battery warns once under threshold'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, true),
  { level: 8, notify: false, dismiss: false, notifiedLowBattery: true },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, true),
  { level: 40, notify: false, dismiss: true, notifiedLowBattery: false },
  'battery clears notified state after recovery'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, false, discharging, 10, true),
  { level: 8, notify: false, dismiss: true, notifiedLowBattery: false },
  'battery dismisses the warning once charging resumes below the threshold'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, false),
  { level: 40, notify: false, dismiss: false, notifiedLowBattery: false },
  'battery dismisses nothing when it never warned'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: false, percentage: 0.5 }, true, discharging, 10, true),
  { level: -1, notify: false, dismiss: true, notifiedLowBattery: false },
  'battery dismisses the warning when the battery goes away'
)
JS
