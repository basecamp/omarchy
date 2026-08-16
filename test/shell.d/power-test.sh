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
  power.parsePacks({
    'pack.0.path': 'BAT0',
    'pack.0.percentage': '90%',
    'pack.0.state': 'holding',
    'pack.1.path': 'BAT1',
    'pack.1.percentage': '0%',
    'pack.1.state': 'charging',
    'pack.1.rate': '3.6W'
  }),
  [
    { path: 'BAT0', percentage: '90%', state: 'holding', size: '', rate: '', cycles: '' },
    { path: 'BAT1', percentage: '0%', state: 'charging', size: '', rate: '3.6W', cycles: '' }
  ],
  'power parses pack rows from battery-status'
)
assertEqual(power.packSummary({ percentage: '0%', state: 'charging', rate: '3.6W' }), '0% · charging · 3.6W', 'power summarizes a charging pack')
assertEqual(power.combinedFractionFromStatus({ percentage: '23%' }), 0.23, 'power reads combined percentage from status')
assertEqual(
  power.combinedEnergyFraction([
    { isPresent: true, isLaptopBattery: true, nativePath: 'BAT0', energy: 22.54, energyCapacity: 25.01 },
    { isPresent: true, isLaptopBattery: true, nativePath: 'BAT1', energy: 0.09, energyCapacity: 71.04 }
  ]).toFixed(4),
  (22.63 / 96.05).toFixed(4),
  'power combines pack energy for the bar fill'
)
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
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.24, state: states.Charging, changeRate: 3.6, timeToFull: 20 * 60 * 60 }, false, states), 'power does not treat a long charge into a second pack as holding')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states), 'power does not flag discharging as threshold')
assert(
  !power.chargeThresholdActiveForPacks(
    [
      { isPresent: true, isLaptopBattery: true, nativePath: 'BAT0', percentage: 0.9, state: states.FullyCharged, changeRate: 0 },
      { isPresent: true, isLaptopBattery: true, nativePath: 'BAT1', percentage: 0.01, state: states.Charging, changeRate: 3.6, timeToFull: 20 * 60 * 60 }
    ],
    false,
    states,
    { state: 'charging' }
  ),
  'power uses the charging pack, not the capped pack, for threshold'
)
assert(
  power.chargeThresholdActiveForPacks([], false, states, { state: 'holding' }),
  'power trusts battery-status holding state'
)
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
assert(/batteryPacks\.length > 1/.test(panelSource), 'power lists packs only when more than one battery is present')
assert(/Model\.parsePacks\(root\.batteryInfo\)/.test(panelSource), 'power reads pack rows from battery-status')
assert(/chargeThresholdActiveForPacks/.test(panelSource), 'power decides holding from every laptop pack')
JS
