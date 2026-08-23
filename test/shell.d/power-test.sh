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
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 1.0, timeToFull: 20 * 3600 }, false, states), 'power does not treat a long charge as a hold')
assert(!power.chargeThresholdActive({ isPresent: true, percentage: 0.5, state: states.Discharging }, false, states), 'power does not flag discharging as threshold')

const dead = { isPresent: true, isLaptopBattery: true, nativePath: 'BAT0', energy: 0, energyCapacity: 20.65, changeRate: 0, percentage: 0, voltage: 0, state: states.PendingCharge }
const emptyLive = { isPresent: true, isLaptopBattery: true, nativePath: 'BAT0', energy: 0, energyCapacity: 23.2, changeRate: 0, percentage: 0, voltage: 11.1, state: states.PendingCharge }
const live = { isPresent: true, isLaptopBattery: true, nativePath: 'BAT1', energy: 20.43, energyCapacity: 20.94, changeRate: 2.17, percentage: 0.98, state: states.Charging }
const display = { isPresent: true, nativePath: '', energy: 20.43, energyCapacity: 41.59, changeRate: 2.17, percentage: 0.49, state: states.Charging }
const packs = [dead, live, display]
assert(!power.isLivePack(dead), 'power treats a 0 V pack as dead')
assert(power.isLivePack(emptyLive), 'power treats a 0% pack with voltage as live')
assertDeepEqual(power.liveLaptopDevices(packs).map((p) => p.nativePath), ['BAT1'], 'power skips a present-but-dead pack')
assertDeepEqual(power.liveLaptopDevices([emptyLive, live, display]).map((p) => p.nativePath), ['BAT0', 'BAT1'], 'power keeps a healthy empty pack beside a live one')
assertDeepEqual(
  power.liveLaptopDevices([dead, live], { 'pack.0.path': 'BAT0', 'pack.1.path': 'BAT1' }).map((p) => p.nativePath),
  ['BAT0', 'BAT1'],
  'power follows CLI-selected pack ids when voltage is missing'
)
assertEqual(power.packPathKey('/sys/class/power_supply/BAT1'), 'BAT1', 'power pack path key is the native-path basename')
assert(power.pathsMatch('/sys/class/power_supply/BAT1', 'BAT1'), 'power matches a sysfs nativePath to a CLI BAT id')
assert(!power.pathsMatch('BAT0', 'BAT1'), 'power does not match distinct pack ids')
const deadSys = Object.assign({}, dead, { nativePath: '/sys/class/power_supply/BAT0' })
const liveSys = Object.assign({}, live, { nativePath: '/sys/class/power_supply/BAT1' })
assertDeepEqual(
  power.liveLaptopDevices([deadSys, liveSys], { 'pack.0.path': 'BAT1' }).map((p) => p.nativePath),
  ['/sys/class/power_supply/BAT1'],
  'power matches CLI pack ids to UPower nativePath suffixes'
)
assertEqual(power.combinedEnergyFraction(packs), 20.43 / 20.94, 'power fill level follows live energy, not DisplayDevice')
assert(!power.chargeThresholdActiveForPacks(packs, false, states, { state: 'holding' }), 'power does not hold while a live pack is charging')
assertEqual(power.viewDevice(packs, display, states).percentage, 20.43 / 20.94, 'power icon uses live energy fraction')
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
assert(/liveLaptopDevices\(powerDevices, opened \? batteryInfo : null\)/.test(panelSource), 'power panel reads live packs instead of DisplayDevice alone')

const firstSample = power.applyEnergySample({}, { energy: '8.4Wh', size: '20.94Wh', rate: '8W', state: 'discharging' }, 1000)
const cliffSample = power.applyEnergySample(firstSample, { energy: '1.3Wh', size: '20.94Wh', rate: '8W', state: 'discharging' }, 61000)
assert(Math.abs(power.parseWh(cliffSample.energy) - 8.4) < 0.05, 'power rejects an EC fuel-gauge cliff that beats measured watts')
assertEqual(
  power.applyEnergySample(firstSample, { energy: '1.3Wh', size: '20.94Wh', rate: '8W', state: 'charging' }, 61000).energy,
  '1.3Wh',
  'power allows an energy drop across a charge/discharge flip'
)
assert(/chargeThresholdActiveForPacks/.test(panelSource), 'power panel uses the multi-pack hold detector')
assert(!/UPower\.displayDevice/.test(panelSource.split('batteryFraction')[1].split('readonly property bool charging')[0]), 'power fill does not fall back to DisplayDevice')
JS
