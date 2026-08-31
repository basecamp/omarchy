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
  power.parseResponsiveStatus('{"available":true,"enabled":true,"health":"ok","reason":"responsive"}'),
  { valid: true, supported: true, installed: true, available: true, enabled: true, health: 'ok', reason: 'responsive' },
  'power parses app launch responsiveness status'
)
assertDeepEqual(
  power.parseResponsiveStatus('{"supported":true,"installed":false,"available":false,"enabled":false,"health":"ok","reason":"ineligible"}'),
  { valid: true, supported: true, installed: false, available: false, enabled: false, health: 'ok', reason: 'ineligible' },
  'power parses supported app launch setup status'
)
assertDeepEqual(
  power.parseResponsiveStatus('not json'),
  { valid: false, supported: false, installed: false, available: false, enabled: false, health: 'blocked', reason: 'status_invalid' },
  'power rejects invalid app launch responsiveness status'
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

assert(/if \(b === Qt\.RightButton\) root\.togglePercentage\(\)/.test(panelSource), 'power right click toggles the bar percentage')
assert(/Object\.assign\([^\n]+showPercentage: !root\.showPercentage[^\n]+\)[\s\S]*updateEntryInline/.test(panelSource), 'power persists the bar percentage setting')
assert(/Math\.round\(root\.batteryFraction \* 100\) \+ "% " \+ root\.batteryIcon\(\)/.test(panelSource), 'power places the percentage before the battery icon')
assert(/openPanelIndicatorWidth:.*showPercentage.*button\.glyphPaintedWidth : 0/.test(panelSource), 'power spans the open-panel mark across the painted percentage block')
assert(/IpcHandler[\s\S]*?function togglePercentage\(\) \{ root\.togglePercentage\(\) \}/.test(panelSource), 'power exposes togglePercentage over IPC')
assert(/manageIpc: false/.test(panelSource), 'power owns its IPC handler so it can extend the target methods')
assert(/command: \["omarchy-app-launch-responsive", "status", "--json"\]/.test(panelSource), 'power discovers app launch responsiveness support')
assert(/"omarchy-app-launch-responsive",[\s\S]*?"set",[\s\S]*?responsiveEnabled \? "off" : "on"/.test(panelSource), 'power toggles app launch responsiveness')
assert(/visible: root\.responsiveVisible[\s\S]*?label: "Faster app launches"/.test(panelSource), 'power only shows the faster app launches toggle when supported')
assert(/enabled: root\.responsiveCanToggle && !root\.responsiveBusy/.test(panelSource), 'power only enables app launch setup in an eligible state')
assert(/"Unplug and select Balanced to set up"/.test(panelSource), 'power explains how to make app launch setup available')
assert(/responsiveInstalled && responsiveHealth === "blocked"/.test(panelSource), 'power flags an installed blocked backend for review')
assert(/!root\.responsiveVisible[\s\S]*?selectProfileByDelta\(dy\)/.test(panelSource), 'power keeps vertical profile navigation when the hardware toggle is hidden')
assert(/function normalizeResponsiveCursor\(\)[\s\S]*?!responsiveVisible && cursorSection === "responsive"[\s\S]*?cursorSection = "profiles"/.test(panelSource), 'power clears a hidden app launch cursor')
JS
