#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const power = requireFromRoot('shell/plugins/panels/power/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/power/Panel.qml', 'utf8')
const states = { Charging: 1, Discharging: 2, FullyCharged: 3, PendingCharge: 4 }

assertEqual(power.selectProfileIndex(0, 1, ['balanced', 'performance']), 1, 'power advances profile selection')
assertEqual(power.selectProfileIndex(1, 1, ['balanced', 'performance']), 1, 'power clamps profile selection')

assertDeepEqual(power.parseKeyValue('time\t2:00\nenergy\t42\n'), { time: '2:00', energy: '42' }, 'power parses key-value output')
assertDeepEqual(
  power.parseProfiles('power-saver\t0\nbalanced\t1\nperformance\t0\n', 5),
  { profiles: ['power-saver', 'balanced', 'performance'], activeProfile: 'balanced', profileIndex: 2 },
  'power parses profile output and clamps selection'
)

assert(power.profileIcon('performance').length > 0, 'power maps profile icons')
assertEqual(power.batteryFraction({ isPresent: true, percentage: 1.5 }), 1, 'power clamps battery fraction')

assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.PendingCharge }, false, states), 'power detects threshold by pending charge state')
assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 0.1, timeToFull: 120 }, false, states), 'power detects threshold by stalled charging')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 1.0, timeToFull: 120 }, false, states), 'power does not flag active charging as threshold')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states), 'power does not flag discharging as threshold')
assertEqual(power.modeLabel({ isPresent: true, percentage: 1, state: states.FullyCharged }, false, states), 'Fully charged', 'power labels full battery')
assertEqual(power.modeLabel({ isPresent: true, percentage: 0.5, state: states.Discharging }, true, states), 'On battery', 'power labels battery mode')
assertEqual(power.modeLabel({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states), 'Charging', 'power treats external power as newer than stale discharging state')
assert(power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Charging }, false, states).length > 0, 'power maps battery icons')
assertEqual(
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Discharging }, false, states),
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Charging, changeRate: 1.0, timeToFull: 120 }, false, states),
  'power shows charging icon when external power is present before battery state refreshes'
)
assertEqual(
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Charging }, true, states),
  power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Discharging }, true, states),
  'power shows battery icon when unplugged before battery state refreshes'
)

// Per-battery cards. The fixture above renumbers the enum, so these use UPower's
// real ordering: Empty sits at 3, where that fixture has FullyCharged.
const deviceStates = { Unknown: 0, Charging: 1, Discharging: 2, Empty: 3, FullyCharged: 4, PendingCharge: 5, PendingDischarge: 6 }
const types = { Battery: 2 }
const displayDevice = { type: types.Battery, powerSupply: true, nativePath: '' }
const bat0 = { type: types.Battery, powerSupply: true, nativePath: 'BAT0' }
const bat1 = { type: types.Battery, powerSupply: true, nativePath: 'BAT1' }
const mouse = { type: types.Battery, powerSupply: false, nativePath: 'hid-dc:2c:26:1b:14:9f-battery' }
const headset = { type: 8, powerSupply: false, nativePath: 'hid-headset' }

assert(power.isPhysicalBattery(bat0, displayDevice, types), 'power counts a power supply battery as the machine\'s own')
assert(!power.isPhysicalBattery(mouse, displayDevice, types), 'power excludes a peripheral battery')
assert(!power.isPhysicalBattery(headset, displayDevice, types), 'power excludes a device that is not a battery')
assert(!power.isPhysicalBattery(displayDevice, displayDevice, types), 'power excludes the aggregate display device')
assert(!power.isPhysicalBattery(bat0, bat0, types), 'power excludes whichever device UPower hands back as the aggregate')
assertDeepEqual(
  power.physicalBatteries([bat1, mouse, displayDevice, bat0], displayDevice, types).map(function(d) { return d.nativePath }),
  ['BAT0', 'BAT1'],
  'power orders batteries by native path and drops everything else'
)

assertEqual(power.deviceStateLabel({ isPresent: true, state: deviceStates.Empty }, deviceStates), 'Empty', 'power labels a drained pack as empty')
assertEqual(power.deviceStateLabel({ isPresent: true, state: deviceStates.Unknown }, deviceStates), 'Idle', 'power labels an unreported state as idle')
assertEqual(power.deviceStateLabel({ isPresent: false }, deviceStates), 'Absent', 'power labels a missing pack as absent')

// The states object lives in Panel.qml, so a member missing there reads as Idle
// no matter what Model.js maps. That is how Empty was lost.
for (const member of ['Charging', 'Discharging', 'Empty', 'FullyCharged', 'PendingCharge', 'PendingDischarge'])
  assert(
    new RegExp(member + ': UPowerDeviceState\\.' + member).test(panelSource),
    `power hands UPower's ${member} state to the per-battery labels`
  )

assert(/if \(b === Qt\.RightButton\) root\.togglePercentage\(\)/.test(panelSource), 'power right click toggles the bar percentage')
assert(/Object\.assign\([^\n]+showPercentage: !root\.showPercentage[^\n]+\)[\s\S]*updateEntryInline/.test(panelSource), 'power persists the bar percentage setting')
assert(/Math\.round\(root\.batteryFraction \* 100\) \+ "% " \+ root\.batteryIcon\(\)/.test(panelSource), 'power places the percentage before the battery icon')
assert(/openPanelIndicatorWidth:.*showPercentage.*button\.glyphPaintedWidth : 0/.test(panelSource), 'power spans the open-panel mark across the painted percentage block')
assert(/IpcHandler[\s\S]*?function togglePercentage\(\) \{ root\.togglePercentage\(\) \}/.test(panelSource), 'power exposes togglePercentage over IPC')
assert(/manageIpc: false/.test(panelSource), 'power owns its IPC handler so it can extend the target methods')
JS
