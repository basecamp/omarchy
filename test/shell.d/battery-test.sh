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
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, false, true),
  { level: 8, notify: true, dismiss: false, notifiedLowBattery: true, staleWarningSwept: true },
  'battery warns once under threshold'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, true, true),
  { level: 8, notify: false, dismiss: false, notifiedLowBattery: true, staleWarningSwept: true },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, true, true),
  { level: 40, notify: false, dismiss: true, notifiedLowBattery: false, staleWarningSwept: true },
  'battery clears the standing warning after recovery'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, false, true),
  { level: 40, notify: false, dismiss: false, notifiedLowBattery: false, staleWarningSwept: true },
  'battery leaves a healthy charge alone'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.08, state: charging }, false, discharging, 10, true, true),
  { level: 8, notify: false, dismiss: true, notifiedLowBattery: false, staleWarningSwept: true },
  'battery clears the standing warning as soon as it is plugged in'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.12, state: discharging }, true, discharging, 10, true, true),
  { level: 12, notify: false, dismiss: false, notifiedLowBattery: true, staleWarningSwept: true },
  'battery stays armed inside the re-arm margin so a boundary wobble cannot stack a second warning'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.16, state: discharging }, true, discharging, 10, true, true),
  { level: 16, notify: false, dismiss: true, notifiedLowBattery: false, staleWarningSwept: true },
  'battery re-arms once the charge climbs clear of the re-arm margin'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: false, percentage: 0.5, state: discharging }, true, discharging, 10, true, true),
  { level: -1, notify: false, dismiss: true, notifiedLowBattery: false, staleWarningSwept: true },
  'battery clears the standing warning when the battery goes away'
)

// A critical toast is restored from disk when the shell process restarts, but
// the latch that remembers sending it is in-process only.
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.4, state: charging }, false, discharging, 10, false, false),
  { level: 40, notify: false, dismiss: true, notifiedLowBattery: false, staleWarningSwept: true },
  'battery sweeps a warning restored by a shell restart that this process never sent'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.4, state: charging }, false, discharging, 10, false, true),
  { level: 40, notify: false, dismiss: false, notifiedLowBattery: false, staleWarningSwept: true },
  'battery sweeps only once per process rather than every check'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: false, percentage: 0, state: discharging }, true, discharging, 10, false, false),
  { level: -1, notify: false, dismiss: false, notifiedLowBattery: false, staleWarningSwept: false },
  'battery does not spend the sweep on a startup tick with no battery reading yet'
)
assertDeepEqual(
  battery.lowBatteryWarningState({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, false, false),
  { level: 8, notify: true, dismiss: false, notifiedLowBattery: true, staleWarningSwept: true },
  'battery warns rather than sweeping when it restarts still low, the send replacing the restored toast'
)
JS
