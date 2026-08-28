#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

battery_service="$ROOT/shell/plugins/services/battery/Service.qml"

# The model decides whether to dismiss; these cover the service acting on that
# decision, which the model tests below cannot reach.
grep -F 'else if (state.dismiss) dismissLowBatteryWarning()' "$battery_service" >/dev/null
grep -F 'dismissProcess.command = ["omarchy-notification-dismiss", lowBatterySummary]' "$battery_service" >/dev/null
grep -F 'readonly property string lowBatterySummary: "Time to recharge!"' "$battery_service" >/dev/null
pass "battery service dismisses the warning by its own summary"

# omarchy-battery-low posts the toast from a spawned process, so a dismiss sent
# while that is still in flight matches nothing and strands the popup that lands
# just after it.
grep -F 'if (warningProcess.running) {' "$battery_service" >/dev/null
grep -F 'pendingDismiss = true' "$battery_service" >/dev/null
grep -F 'onExited: if (root.pendingDismiss) root.dismissLowBatteryWarning()' "$battery_service" >/dev/null
pass "battery service holds a dismiss until the in-flight warning has posted"

# Unplugged again before that warning finished: its toast is the current one,
# so the queued dismiss must not fire on the way out.
grep -F 'pendingDismiss = false' "$battery_service" >/dev/null
grep -B2 -F 'if (warningProcess.running) return' "$battery_service" | grep -F 'pendingDismiss = false' >/dev/null
pass "battery service drops a queued dismiss when a fresh warning supersedes it"

# The summary the service dismisses has to be the headline the command sends.
grep -F '"Time to recharge!"' "$ROOT/bin/omarchy-battery-low" >/dev/null
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
