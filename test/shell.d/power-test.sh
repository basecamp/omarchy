#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const power = requireFromRoot('shell/plugins/panels/power/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/power/Panel.qml', 'utf8')
const states = { Charging: 1, Discharging: 2, Empty: 3, FullyCharged: 4, PendingCharge: 5, PendingDischarge: 6 }

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

assertEqual(power.batteryName({ nativePath: 'BAT0' }), 'BAT0', 'power names battery from native path')
assertEqual(power.batteryName({ nativePath: '/sys/devices/.../BAT1' }), 'BAT1', 'power extracts battery name from full native path')
assertEqual(power.batteryName({ nativePath: '/sys/devices/.../BAT1/', model: 'AB12' }), 'BAT1', 'power ignores trailing slash in native path')
assertEqual(power.batteryName({ model: 'AB12' }), 'AB12', 'power falls back to the model for battery name')
assertEqual(power.batteryName({}), 'Battery', 'power defaults the battery name')

assertEqual(power.batteryStateLabel({ state: states.Charging }, states), 'Charging', 'power labels charging battery')
assertEqual(power.batteryStateLabel({ state: states.Discharging }, states), 'Discharging', 'power labels discharging battery')
assertEqual(power.batteryStateLabel({ state: states.Empty }, states), 'Empty', 'power labels empty battery')
assertEqual(power.batteryStateLabel({ state: states.FullyCharged }, states), 'Full', 'power labels full battery')
assertEqual(power.batteryStateLabel({ state: states.PendingCharge }, states), 'Pending charge', 'power labels pending-charge battery')
assertEqual(power.batteryStateLabel({ state: states.PendingDischarge }, states), 'Pending discharge', 'power labels pending-discharge battery')
assertEqual(power.batteryStateLabel({}, states), '', 'power leaves unknown battery state unlabeled')

assertEqual(power.batteryPercentLabel({ percentage: 0.423 }), '42', 'power formats battery percentage')
assertEqual(power.batteryPercentLabel({ percentage: 0.999 }), '100', 'power rounds battery percentage up')
assertEqual(power.batteryPercentLabel({}), '—', 'power reports missing battery percentage')
assertEqual(power.batteryChargeLabel({ percentage: 0.42, state: states.Charging }, states), '42% · Charging', 'power formats charge and state')
assertEqual(power.batteryChargeLabel({ percentage: 0.42 }, states), '42%', 'power omits the separator without a known state')

assertEqual(power.batteryCapacityLabel({ energyCapacity: 19.02 }), '19.0 Wh', 'power formats battery capacity')
assertEqual(power.batteryCapacityLabel({ energyCapacity: 0 }), '—', 'power reports zero battery capacity')
assertEqual(power.batteryCapacityLabel({}), '—', 'power reports missing battery capacity')

assert(/UPowerDeviceState\.Empty/.test(panelSource), 'power maps empty battery state')
assert(/UPowerDeviceState\.PendingDischarge/.test(panelSource), 'power maps pending-discharge battery state')
assert(/UPowerDeviceType\.Battery/.test(panelSource), 'power filters physical batteries from the UPower device list')
assert(/!device\.isPresent/.test(panelSource), 'power excludes absent physical batteries')
assert(/UPower\.devices\.values/.test(panelSource), 'power enumerates the Quickshell UPower object model')
assert(/root\.batteries\.length > 1/.test(panelSource), 'power only shows the per-battery breakdown on multi-battery systems')
assert(/PanelSectionHeader[\s\S]*?text: "BATTERIES"/.test(panelSource), 'power heads the per-battery breakdown')
assert(/Model\.batteryIcon\(device, root\.discharging, upowerStates\(\)\)/.test(panelSource), 'power lists each battery in the bar button')
assert(/batteries\.length > 1 && !vertical/.test(panelSource), 'power keeps vertical bars on the compact aggregate battery')
assert(/showPercentage && !vertical \? 2 : 1/.test(panelSource), 'power keeps percentage sizing compact on vertical bars')
assert(/batteries\.length \* 2/.test(panelSource), 'power widens the bar button for multiple batteries')
assert(/readonly property var batteries: collectBatteries\(\)/.test(panelSource), 'power reacts to changes in the UPower battery list')

assert(/if \(b === Qt\.RightButton\) root\.togglePercentage\(\)/.test(panelSource), 'power right click toggles the bar percentage')
assert(/Object\.assign\([^\n]+showPercentage: !root\.showPercentage[^\n]+\)[\s\S]*updateEntryInline/.test(panelSource), 'power persists the bar percentage setting')
assert(/Math\.round\(root\.batteryFraction \* 100\) \+ "% " \+ root\.batteryIcon\(\)/.test(panelSource), 'power places the percentage before the battery icon')
assert(/openPanelIndicatorWidth:.*showPercentage.*button\.glyphPaintedWidth : 0/.test(panelSource), 'power spans the open-panel mark across the painted percentage block')
assert(/IpcHandler[\s\S]*?function togglePercentage\(\) \{ root\.togglePercentage\(\) \}/.test(panelSource), 'power exposes togglePercentage over IPC')
assert(/manageIpc: false/.test(panelSource), 'power owns its IPC handler so it can extend the target methods')
JS
