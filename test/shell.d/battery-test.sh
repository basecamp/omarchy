#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const battery = requireFromRoot('shell/plugins/services/battery/BatteryModel.js')
const power = requireFromRoot('shell/plugins/panels/power/Model.js')
const serviceSource = fs.readFileSync(root + '/shell/plugins/services/battery/Service.qml', 'utf8')
const criticalSource = fs.readFileSync(root + '/bin/omarchy-battery-critical', 'utf8')
const states = { Charging: 1, Discharging: 2, FullyCharged: 3, PendingCharge: 4 }
const discharging = 1

assertEqual(battery.LOW_BATTERY_WARN_PERCENT, 10, 'battery warn mark stays 10%')
assertEqual(battery.LOW_BATTERY_ACTION_PERCENT, 2, 'battery action mark stays 2%')
assertEqual(battery.batteryPercentage({ isPresent: true, percentage: 0.126 }), 13, 'battery rounds display percentage')
assertEqual(battery.batteryPercentage({ isPresent: false, percentage: 0.5 }), -1, 'battery reports missing battery')
assert(battery.isDischarging({ isPresent: true, state: discharging }, true, discharging), 'battery detects discharging state')
assert(!battery.isDischarging({ isPresent: true, state: discharging }, false, discharging), 'battery requires on-battery state')

assertDeepEqual(
  battery.shouldWarnLowBattery(0.08, true, true, false),
  { level: 8, notify: true, notifiedLowBattery: true },
  'battery warns once under live 10%'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(0.08, true, true, true),
  { level: 8, notify: false, notifiedLowBattery: true },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(0.4, true, true, true),
  { level: 40, notify: false, notifiedLowBattery: false },
  'battery clears notified state after live recovery'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(0.05, false, true, false),
  { level: 5, notify: false, notifiedLowBattery: false },
  'battery does not warn on AC'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(0.05, true, false, false),
  { level: 5, notify: false, notifiedLowBattery: false },
  'battery does not warn while charging'
)
assertDeepEqual(
  battery.shouldWarnLowBattery(-1, true, true, false),
  { level: -1, notify: false, notifiedLowBattery: false },
  'battery does not warn without a live fraction'
)

assertDeepEqual(
  battery.shouldActCriticalBattery(0.02, true, true, false),
  { level: 2, act: true, actedCriticalBattery: true },
  'battery acts at live 2% while discharging on battery'
)
assertDeepEqual(
  battery.shouldActCriticalBattery(0.10, true, true, false),
  { level: 10, act: false, actedCriticalBattery: false },
  'battery does not act at the 10% warn mark'
)
assertDeepEqual(
  battery.shouldActCriticalBattery(0.01, false, true, false),
  { level: 1, act: false, actedCriticalBattery: false },
  'battery does not act on AC'
)
assertDeepEqual(
  battery.shouldActCriticalBattery(0.01, true, true, true),
  { level: 1, act: false, actedCriticalBattery: true },
  'battery acts only once at critical'
)

const dead = { isPresent: true, isLaptopBattery: true, nativePath: 'BAT0', energy: 0, energyCapacity: 23.2, changeRate: 0, percentage: 0, voltage: 0, state: states.PendingCharge }
const live = { isPresent: true, isLaptopBattery: true, nativePath: 'BAT1', energy: 8.4, energyCapacity: 20.94, changeRate: -8, percentage: 0.4, voltage: 11.2, state: states.Discharging }
const liveFraction = power.combinedEnergyFraction([dead, live])
assert(liveFraction > 0.39 && liveFraction < 0.41, 'live remaining energy ignores a present-but-dead pack')
assertDeepEqual(
  battery.shouldWarnLowBattery(liveFraction, true, true, false),
  { level: 40, notify: false, notifiedLowBattery: false },
  'dead pack cannot pull warn to empty while the live pack is above 10%'
)
assertDeepEqual(
  battery.shouldActCriticalBattery(liveFraction, true, true, false),
  { level: 40, act: false, actedCriticalBattery: false },
  'dead pack cannot pull critical action while the live pack is above 2%'
)

const first = power.applyEnergySample({}, { energy: '8.4Wh', size: '20.94Wh', rate: '8W', state: 'discharging' }, 1e6)
const cliffed = power.applyEnergySample(first, { energy: '1.3Wh', size: '20.94Wh', rate: '8W', state: 'discharging' }, 1e6 + 60 * 1000)
assert(Math.abs(power.parseWh(cliffed.energy) - 8.4) < 0.05, 'EC cliff 8.4→1.3 Wh in 60s at 8W keeps ~8.4 Wh')
const cliffFraction = power.combinedFractionFromStatus(cliffed)
assert(cliffFraction > 0.10, 'rejected cliff stays above the 10% warn mark')
assertEqual(battery.shouldWarnLowBattery(cliffFraction, true, true, false).notify, false, 'EC cliff must not notify')
assertEqual(battery.shouldActCriticalBattery(cliffFraction, true, true, false).act, false, 'EC cliff must not sleep')

const snap = power.liveEnergySnapshot(
  [dead, { isPresent: true, isLaptopBattery: true, nativePath: 'BAT1', energy: 1.3, energyCapacity: 20.94, changeRate: -8, percentage: 0.06, voltage: 10.6, state: states.Discharging }],
  null,
  first,
  1e6 + 60 * 1000,
  states
)
assert(Math.abs(snap.fraction - cliffFraction) < 0.02, 'liveEnergySnapshot applies the same cliff reject')
assertEqual(snap.discharging, true, 'liveEnergySnapshot reports discharging from pack state')

assert(!/UPower\.displayDevice/.test(serviceSource), 'battery service does not gate on DisplayDevice')
assert(/PowerModel\.liveEnergySnapshot/.test(serviceSource), 'battery service snapshots live remaining energy')
assert(/BatteryModel\.shouldWarnLowBattery/.test(serviceSource), 'battery service warns from live remaining energy')
assert(/BatteryModel\.shouldActCriticalBattery/.test(serviceSource), 'battery service acts from live remaining energy')
assert(/omarchy-battery-critical/.test(serviceSource), 'battery service wires the 2% critical command')
assert(/suspend-then-hibernate/.test(criticalSource), 'critical command requests suspend-then-hibernate')
assert(/omarchy:hidden=true/.test(criticalSource), 'critical command is hidden')
JS
