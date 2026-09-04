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

const fs = require('fs')
const serviceSource = fs.readFileSync(root + '/shell/plugins/services/battery/Service.qml', 'utf8')
const dismissMatch = serviceSource.match(/dismissProcess\.command = \["omarchy-notification-dismiss", "([^"]+)"\]/)
assert(!!dismissMatch, 'battery service dismisses the low-battery toast through Omarchy command')
assert(/if \(!UPower\.onBattery && persisted\.notifiedLowBattery\) root\.dismissLowBatteryWarning\(\)/.test(serviceSource), 'battery service dismisses the low-battery toast on plug-in')

// The dismiss above matches by title, independently of the title
// omarchy-battery-low sends — assert they're the same string so the two
// can't silently drift apart.
const sendSource = fs.readFileSync(root + '/bin/omarchy-battery-low', 'utf8')
const sendMatch = sendSource.match(/omarchy-notification-send[^\n]*?"([^"\n]+)"/)
assert(!!sendMatch, 'omarchy-battery-low sends a titled notification')
assertEqual(dismissMatch[1], sendMatch[1], 'battery service dismisses the exact toast title omarchy-battery-low sends')
JS
