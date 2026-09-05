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

assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.PendingCharge }, false, states, '75-80%'), 'power detects threshold by pending charge state')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0, state: states.PendingCharge }, false, states, '75-80%'), 'power does not flag a pack below the hold band as threshold')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.5, state: states.PendingCharge }, false, states), 'power does not flag pending charge as threshold without a limit')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.5, state: states.PendingCharge }, false, states, '0-100%'), 'power reads a 100% end threshold as no limit')
assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.PendingCharge }, false, states, '80%'), 'power holds at a single-value threshold')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.7, state: states.PendingCharge }, false, states, '80%'), 'power does not hold below a single-value threshold')
assertEqual(power.chargeHoldFloor('0-80%'), 0.8, 'power reads a zero start threshold as no start band')
assertEqual(
  power.modeLabel({ isPresent: true, percentage: 0, state: states.PendingCharge }, false, states, '75-80%'),
  'Charging',
  'power does not label a stalled pack below the band as Threshold'
)
assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 0.1, timeToFull: 120 }, false, states, '75-80%'), 'power detects threshold by stalled charging')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 1.0, timeToFull: 120 }, false, states, '75-80%'), 'power does not flag active charging as threshold')

// A stalled charge is only a hold when a limit is there to hold it, and only
// once the pack has reached that limit. omarchy-battery-status gates its own
// charging branch the same way; these two layers describe the same battery.
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 0.1, timeToFull: 120 }, false, states), 'power does not flag a stalled charge as threshold without a limit')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.4, state: states.Charging, changeRate: 0.1, timeToFull: 120 }, false, states, '75-80%'), 'power does not flag a stalled charge below the limit as threshold')
assertEqual(
  power.modeLabel({ isPresent: true, percentage: 0.4, state: states.Charging, changeRate: 0.1, timeToFull: 120 }, false, states, '75-80%'),
  'Charging',
  'power labels a slow charge below the limit as charging'
)

// FullyCharged short of full is the same claim: with no limit configured it is
// a worn pack reporting its own ceiling, not a hold.
assert(power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.FullyCharged }, false, states, '75-80%'), 'power detects a limit holding below full')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.FullyCharged }, false, states), 'power does not flag a worn pack reporting full early as threshold')
assertEqual(
  power.modeLabel({ isPresent: true, percentage: 0.8, state: states.FullyCharged }, false, states),
  'Fully charged',
  'power labels a worn pack reporting full early as fully charged'
)
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

assert(/if \(b === Qt\.RightButton\) root\.togglePercentage\(\)/.test(panelSource), 'power right click toggles the bar percentage')
assert(/Object\.assign\([^\n]+showPercentage: !root\.showPercentage[^\n]+\)[\s\S]*updateEntryInline/.test(panelSource), 'power persists the bar percentage setting')
assert(/Math\.round\(root\.batteryFraction \* 100\) \+ "% " \+ root\.batteryIcon\(\)/.test(panelSource), 'power places the percentage before the battery icon')
assert(/openPanelIndicatorWidth:.*showPercentage.*button\.glyphPaintedWidth : 0/.test(panelSource), 'power spans the open-panel mark across the painted percentage block')
assert(/IpcHandler[\s\S]*?function togglePercentage\(\) \{ root\.togglePercentage\(\) \}/.test(panelSource), 'power exposes togglePercentage over IPC')
assert(/manageIpc: false/.test(panelSource), 'power owns its IPC handler so it can extend the target methods')
JS
