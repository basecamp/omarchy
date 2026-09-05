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
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, false, discharging, 10, false),
  { level: 8, notify: false, notifiedLowBattery: false },
  'battery does not warn while on AC even if percentage is low'
)

const serviceSource = require('fs').readFileSync(root + '/shell/plugins/services/battery/Service.qml', 'utf8')
assert(/triggeredOnStart:\s*false/.test(serviceSource), 'battery defers the first low-battery check past shell start')
assert(/lowBatteryChecksReady:\s*false/.test(serviceSource), 'battery gates low-battery checks until UPower settles')
assert(/lowBatteryChecksReady\s*=\s*true[\s\S]*checkBattery\(\)/.test(serviceSource), 'battery enables checks on the settle timer before the first evaluation')
assert(/function checkBattery\(\)\s*\{[\s\S]*if\s*\(\s*!lowBatteryChecksReady\s*\)\s*return/.test(serviceSource), 'battery skips low-battery warnings until settle completes')
assert(/onOnBatteryChanged\(\)\s*\{[\s\S]*applyPowerProfile\(\)[\s\S]*checkBattery\(\)/.test(serviceSource), 'battery still applies power profiles immediately on charger changes')
JS
