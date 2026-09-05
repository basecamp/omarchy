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
assertDeepEqual(
  power.parseProfiles('power-saver\t0\nbalanced\t1\n', 0),
  { profiles: ['power-saver', 'balanced'], activeProfile: 'balanced', profileIndex: 0 },
  'power accepts fallback platforms without a performance profile'
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

assert(/if \(root\.batteryPresent\) root\.togglePercentage\(\)/.test(panelSource), 'power limits the percentage toggle to battery hardware')
assert(/Object\.assign\([^\n]+showPercentage: !root\.showPercentage[^\n]+\)[\s\S]*updateEntryInline/.test(panelSource), 'power persists the bar percentage setting')
assert(/percentageVisible: batteryPresent && showPercentage && !button\.vertical/.test(panelSource), 'power suppresses percentage text without battery hardware')
assert(/return batteryPresent \? batteryIcon\(\) : ""/.test(panelSource), 'power uses an AC plug icon without battery hardware')
assert(/Math\.round\(root\.batteryFraction \* 100\) \+ "% " \+ root\.barIcon\(\)/.test(panelSource), 'power places the percentage before the battery icon')
assert(/openPanelIndicatorWidth: percentageVisible \? button\.glyphPaintedWidth : 0/.test(panelSource), 'power spans the open-panel mark across the painted percentage block')
assert(/open: root\.opened\n/.test(panelSource), 'power panel opens without requiring battery hardware')
assert(!/if \(!batteryPresent\) \{\s*close\(\)/.test(panelSource), 'power does not self-close without battery hardware')
assert(/idleService: bar\?\.shell\?\.firstPartyServiceFor\("omarchy\.idle"\)/.test(panelSource), 'power reads the shared screensaver state')
assert(/function open\(\) \{\s*if \(screensaverActive\) return\s*controller\.show\(\)\s*\}/.test(panelSource), 'power refuses to open over the screensaver')
assert(/onScreensaverActiveChanged: if \(screensaverActive && opened\) close\(\)/.test(panelSource), 'power closes if the screensaver starts while it is open')
assert(/if \(batteryPresent && !systemProc\.running\) systemProc\.running = true/.test(panelSource), 'power keeps unused system-stat polling off battery-less hardware')
assert(/visible: root\.batteryPresent[\s\S]*text: "Battery"/.test(panelSource), 'power keeps the battery hero hardware-scoped')
assert(/PanelSeparator \{\s*visible: root\.batteryPresent/.test(panelSource), 'power hides the battery separator without battery hardware')
assert(/text: "AVAILABLE POWER PROFILES"/.test(panelSource), 'power presents daemon-advertised profiles as the complete available set')
assert(/IpcHandler[\s\S]*?function togglePercentage\(\) \{ root\.togglePercentage\(\) \}/.test(panelSource), 'power exposes togglePercentage over IPC')
assert(/manageIpc: false/.test(panelSource), 'power owns its IPC handler so it can extend the target methods')
JS
