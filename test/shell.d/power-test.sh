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

assertEqual(power.batteryDisplayMode(undefined, false), 'icon', 'power defaults to the icon-only display')
assertEqual(power.batteryDisplayMode(undefined, true), 'percentage-before', 'power preserves the legacy percentage setting')
assertEqual(power.batteryDisplayMode('invalid', true), 'percentage-before', 'power falls back from an invalid display mode')
assertEqual(power.nextBatteryDisplayMode('icon'), 'percentage-before', 'power cycles from icon to percentage before icon')
assertEqual(power.nextBatteryDisplayMode('percentage-before'), 'percentage-after', 'power cycles from percentage before icon to percentage after icon')
assertEqual(power.nextBatteryDisplayMode('percentage-after'), 'icon', 'power cycles from percentage after icon back to icon')
assertEqual(power.batteryBarText('icon', 0.51, 'BATTERY', false), 'BATTERY', 'power renders the icon-only display')
assertEqual(power.batteryBarText('percentage-before', 0.51, 'BATTERY', false), '51% BATTERY', 'power renders percentage before the icon')
assertEqual(power.batteryBarText('percentage-after', 0.51, 'BATTERY', false), 'BATTERY 51%', 'power renders percentage after the icon')
assertEqual(power.batteryBarText('percentage-after', 0.51, 'BATTERY', true), 'BATTERY', 'power hides percentage in vertical bars')

assert(/if \(b === Qt\.RightButton\) root\.togglePercentage\(\)/.test(panelSource), 'power right click cycles the bar display')
assert(/displayMode: Model\.nextBatteryDisplayMode\(root\.displayMode\)[\s\S]*updateEntryInline/.test(panelSource), 'power persists the selected display mode')
assert(/Model\.batteryBarText\(root\.displayMode, root\.batteryFraction, root\.batteryIcon\(\), vertical\)/.test(panelSource), 'power delegates bar text placement to the display model')
assert(/slotSize: Style\.bar\.iconSlot \* \(root\.percentageShown && !vertical \? 2 : 1\)/.test(panelSource), 'power keeps percentage hidden and icon-sized in vertical bars')
assert(/openPanelIndicatorWidth:.*percentageShown.*button\.glyphPaintedWidth : 0/.test(panelSource), 'power spans the open-panel mark across the painted percentage block')
assert(/IpcHandler[\s\S]*?function togglePercentage\(\) \{ root\.togglePercentage\(\) \}/.test(panelSource), 'power exposes togglePercentage over IPC')
assert(/manageIpc: false/.test(panelSource), 'power owns its IPC handler so it can extend the target methods')
JS
