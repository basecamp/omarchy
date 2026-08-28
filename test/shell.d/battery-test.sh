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
# just after it. A dismiss already running cannot carry a second request either.
grep -F 'if (warningProcess.running || dismissProcess.running) {' "$battery_service" >/dev/null
grep -F 'pendingDismiss = true' "$battery_service" >/dev/null
pass "battery service holds a dismiss while either process is in flight"

# checkBattery clears the latch before dismissing and `dismiss` is only computed
# from that latch, so a request dropped here is never recomputed and the toast
# that never expires stays up for good. Both processes must replay it, and the
# pending flag may only clear on the path that actually issues the command.
(( $(grep -c 'onExited: if (root.pendingDismiss) root.dismissLowBatteryWarning()' "$battery_service") == 2 )) ||
  fail "both the warning and the dismiss replay a held dismiss when they exit"
pass "both the warning and the dismiss replay a held dismiss when they exit"
grep -A6 -F 'function dismissLowBatteryWarning() {' "$battery_service" | grep -A1 -F 'pendingDismiss = false' | grep -F 'dismissProcess.command' >/dev/null
pass "battery service clears the pending dismiss only when it issues one"

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
