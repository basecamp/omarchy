#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const battery = requireFromRoot('shell/plugins/services/battery/BatteryModel.js')
const discharging = 1

assertEqual(battery.batteryPercentage({ isPresent: true, percentage: 0.126 }), 13, 'battery rounds display percentage')
assertEqual(battery.batteryPercentage({ isPresent: false, percentage: 0.5 }), -1, 'battery reports missing battery')
assert(battery.isDischarging({ isPresent: true, state: discharging }, true, discharging), 'battery detects discharging state')
assert(!battery.isDischarging({ isPresent: true, state: discharging }, false, discharging), 'battery requires on-battery state')

assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, false),
  { level: 8, notify: true, notifiedLowBattery: true },
  'battery warns once under threshold'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, true),
  { level: 8, notify: false, notifiedLowBattery: true },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, true),
  { level: 40, notify: false, notifiedLowBattery: false },
  'battery clears notified state after recovery'
)

// AC online status can flap while still critically low (UCSI/PD). The latch must
// survive onBattery false so onOnBatteryChanged cannot re-arm a toast storm.
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, false, discharging, 10, true),
  { level: 8, notify: false, notifiedLowBattery: true },
  'battery keeps the low latch across an AC-online flap'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, true),
  { level: 8, notify: false, notifiedLowBattery: true },
  'battery does not re-notify after an AC flap while still low'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, false, discharging, 10, false),
  { level: 8, notify: false, notifiedLowBattery: false },
  'battery does not latch from AC-only low readings without a discharge warning'
)
// A missing reading is another blip the latch has to survive, or a dropped
// UPower device re-arms the same storm the AC flap used to.
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: false, percentage: 0.08, state: discharging }, true, discharging, 10, true),
  { level: -1, notify: false, notifiedLowBattery: true },
  'battery keeps the low latch while the device reading is missing'
)

// Simulate the issue #9670 flap loop: one warning, then many AC toggles.
;(function () {
  const device = { isPresent: true, percentage: 0.08, state: discharging }
  let notified = false
  let warnings = 0
  for (let i = 0; i < 20; i++) {
    const onBattery = i === 0 || i % 2 === 1
    const state = battery.shouldWarnLowBattery(device, onBattery, discharging, 10, notified)
    if (state.notify) warnings++
    notified = state.notifiedLowBattery
  }
  assertEqual(warnings, 1, 'battery emits a single warning across repeated AC flaps while low')
})()
JS
