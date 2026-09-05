#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const battery = requireFromRoot('shell/plugins/services/battery/BatteryModel.js')
const discharging = 1
const cooldown = 60000

assertEqual(battery.batteryPercentage({ isPresent: true, percentage: 0.126 }), 13, 'battery rounds display percentage')
assertEqual(battery.batteryPercentage({ isPresent: false, percentage: 0.5 }), -1, 'battery reports missing battery')
assert(battery.isDischarging({ isPresent: true, state: discharging }, true, discharging), 'battery detects discharging state')
assert(!battery.isDischarging({ isPresent: true, state: discharging }, false, discharging), 'battery requires on-battery state')

const low = { isPresent: true, percentage: 0.08, state: discharging }
const healthy = { isPresent: true, percentage: 0.4, state: discharging }

assertDeepEqual(
  battery.shouldWarnLowBattery(low, true, discharging, 10, false, 0, 1000, cooldown),
  { level: 8, notify: true, notifiedLowBattery: true, lastNotifiedAt: 1000 },
  'battery warns once under threshold'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(low, true, discharging, 10, true, 1000, 2000, cooldown),
  { level: 8, notify: false, notifiedLowBattery: true, lastNotifiedAt: 1000 },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(healthy, true, discharging, 10, true, 1000, 2000, cooldown),
  { level: 40, notify: false, notifiedLowBattery: false, lastNotifiedAt: 1000 },
  'battery clears notified state after recovery'
)

// A weak charger flips the battery in and out of discharging on the threshold,
// clearing the latch each time; the cooldown is what stops the toast storm.
assertDeepEqual(
  battery.shouldWarnLowBattery(low, true, discharging, 10, false, 1000, 31000, cooldown),
  { level: 8, notify: false, notifiedLowBattery: true, lastNotifiedAt: 1000 },
  'battery holds the warning inside the cooldown'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(low, true, discharging, 10, false, 1000, 61000, cooldown),
  { level: 8, notify: true, notifiedLowBattery: true, lastNotifiedAt: 61000 },
  'battery warns again once the cooldown expires'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: false }, true, discharging, 10, false, 1000, 61000, cooldown),
  { level: -1, notify: false, notifiedLowBattery: false, lastNotifiedAt: 1000 },
  'battery keeps the last warning time when no battery is present'
)
JS
