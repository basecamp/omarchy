#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const power = requireFromRoot('shell/plugins/panels/power/Model.js')
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
assertEqual(power.modeLabel({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states), 'Draining on AC', 'power labels plugged-but-draining distinctly from on-battery')
assert(power.batteryIcon({ isPresent: true, percentage: 0.4, state: states.Charging }, false, states).length > 0, 'power maps battery icons')

// Plugged in but still draining (load exceeds charger) is distinct from being
// on battery: the charger IS attached, so it must not read like on-battery.
assert(power.pluggedButDraining({ isPresent: true, state: states.Discharging }, false, states), 'power detects plugged-but-draining (AC present, still discharging)')
assert(!power.pluggedButDraining({ isPresent: true, state: states.Discharging }, true, states), 'power does not flag on-battery discharge as plugged-but-draining')
assert(!power.pluggedButDraining({ isPresent: true, state: states.Charging }, false, states), 'power does not flag charging as plugged-but-draining')

// The icon must differ from the on-battery glyph (keeps its bolt) and match the
// charging-family glyph at the same level. Compared relationally to avoid
// hard-coding the nerd-font glyphs.
const drainingIcon = power.batteryIcon({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states)
const onBatteryIcon = power.batteryIcon({ isPresent: true, percentage: 0.5, state: states.Discharging }, true, states)
const chargingIcon = power.batteryIcon({ isPresent: true, percentage: 0.5, state: states.Charging, changeRate: 1.0, timeToFull: 120 }, false, states)
assert(drainingIcon !== onBatteryIcon, 'power distinguishes plugged-but-draining from on-battery discharge')
assertEqual(drainingIcon, chargingIcon, 'power keeps the charging/bolt glyph when plugged but draining')
JS
