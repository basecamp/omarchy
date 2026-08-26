#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const battery = requireFromRoot('shell/plugins/services/battery/BatteryModel.js')
const discharging = 1
const charging = 2

assertEqual(battery.batteryPercentage({ isPresent: true, percentage: 0.126 }), 13, 'battery rounds display percentage')
assertEqual(battery.batteryPercentage({ isPresent: false, percentage: 0.5 }), -1, 'battery reports missing battery')
assert(battery.isDischarging({ isPresent: true, state: discharging }, true, discharging), 'battery detects discharging state')
assert(!battery.isDischarging({ isPresent: true, state: discharging }, false, discharging), 'battery requires on-battery state')

assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, false),
  { level: 8, notify: true, dismiss: false, notifiedLowBattery: true },
  'battery warns once under threshold'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, true),
  { level: 8, notify: false, dismiss: false, notifiedLowBattery: true },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, true),
  { level: 40, notify: false, dismiss: true, notifiedLowBattery: false },
  'battery clears the standing warning after recovery'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, false),
  { level: 40, notify: false, dismiss: false, notifiedLowBattery: false },
  'battery leaves a healthy charge alone'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.08, state: charging }, false, discharging, 10, true),
  { level: 8, notify: false, dismiss: true, notifiedLowBattery: false },
  'battery clears the standing warning as soon as it is plugged in'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.12, state: discharging }, true, discharging, 10, true),
  { level: 12, notify: false, dismiss: false, notifiedLowBattery: true },
  'battery stays armed inside the re-arm margin so a boundary wobble cannot stack a second warning'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.16, state: discharging }, true, discharging, 10, true),
  { level: 16, notify: false, dismiss: true, notifiedLowBattery: false },
  'battery re-arms once the charge climbs clear of the re-arm margin'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: false, percentage: 0.5, state: discharging }, true, discharging, 10, true),
  { level: -1, notify: false, dismiss: true, notifiedLowBattery: false },
  'battery clears the standing warning when the battery goes away'
)
JS
