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
assert(power.isBatteryLow({ isPresent: true, percentage: 0.1, state: states.Discharging }, true, 10), 'power flags low battery at the threshold while discharging')
assert(power.isBatteryLow({ isPresent: true, percentage: 0.08, state: states.Discharging }, true, 10), 'power flags low battery under the threshold while discharging')
assert(!power.isBatteryLow({ isPresent: true, percentage: 0.11, state: states.Discharging }, true, 10), 'power does not flag low battery above the threshold')
assert(power.isBatteryLow({ isPresent: true, percentage: 0.104, state: states.Discharging }, true, 10), 'power rounds like the low-battery notification so both switch together at 10.4%')
assert(!power.isBatteryLow({ isPresent: true, percentage: 0.05, state: states.Charging }, false, 10), 'power does not flag low battery while charging')
assert(!power.isBatteryLow({ isPresent: false, percentage: 0.05, state: states.Discharging }, true, 10), 'power does not flag low battery when no battery is present')
assert(power.isBatteryLow({ isPresent: true, percentage: 0.05, state: states.Discharging }, true, 5), 'power flags the danger tier at 5%')
assert(!power.isBatteryLow({ isPresent: true, percentage: 0.06, state: states.Discharging }, true, 5), 'power does not flag the danger tier above 5%')
assert(power.isBatteryLow({ isPresent: true, percentage: 0.02, state: states.Discharging }, true, 2), 'power flags the critical (blinking) tier at 2%')
assert(!power.isBatteryLow({ isPresent: true, percentage: 0.03, state: states.Discharging }, true, 2), 'power does not flag the critical tier above 2%')
assert(power.isBatteryLow({ isPresent: true, percentage: 0.05, state: states.Charging }, true, 10), 'power trusts onBattery over a stale Charging state left over from just before a plug event')
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
assert(/readonly property bool batteryWarning: Model\.isBatteryLow\(/.test(panelSource), 'power derives batteryWarning from the shared model function')
assert(/readonly property bool batteryDanger: Model\.isBatteryLow\(/.test(panelSource), 'power derives batteryDanger from the shared model function')
assert(/readonly property bool batteryCritical: Model\.isBatteryLow\(/.test(panelSource), 'power derives batteryCritical from the shared model function')
assert(/active: root\.batteryWarning[\s\S]*?activeColor: root\.batteryDanger[\s\S]*?blinking: root\.batteryCritical/.test(panelSource), 'power turns the bar icon yellow at warning, red at danger, and blinking at critical')
JS
