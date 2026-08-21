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

assertDeepEqual(
  battery.observePowerSource(false, true, false),
  { recordPluggedAt: false, powerSourceInitialized: true, wasOnBattery: false },
  'battery initializes power-source state without recording'
)
assertDeepEqual(
  battery.observePowerSource(true, true, false),
  { recordPluggedAt: true, powerSourceInitialized: true, wasOnBattery: false },
  'battery records battery-to-AC transition'
)
assertDeepEqual(
  battery.observePowerSource(true, false, true),
  { recordPluggedAt: false, powerSourceInitialized: true, wasOnBattery: true },
  'battery does not record AC-to-battery transition'
)
assert(!battery.observePowerSource(true, true, true).recordPluggedAt, 'battery ignores unchanged battery state')
assert(!battery.observePowerSource(true, false, false).recordPluggedAt, 'battery ignores unchanged AC state')
JS
