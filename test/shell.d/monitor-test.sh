#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const monitor = requireFromRoot('shell/plugins/panels/monitor/Model.js')

assertEqual(monitor.clampBrightness(0), 1, 'monitor clamps minimum brightness')
assertEqual(monitor.clampBrightness(101), 100, 'monitor clamps maximum brightness')
assertEqual(monitor.clampBrightness(42.4), 42, 'monitor rounds brightness')
assertEqual(monitor.clampBrightness('nope'), 1, 'monitor rejects invalid brightness')

assertEqual(monitor.normalizeScale('1.250'), '1.25', 'monitor normalizes fractional scale')
assertEqual(monitor.normalizeScale('nope'), '', 'monitor rejects invalid scale')
assertEqual(monitor.cleanScale(3, 1280, 800), '3.2', 'monitor matches clean VM scale')
assertEqual(monitor.cleanScale(1.25, 1280, 800), '1.25', 'monitor preserves an already clean scale')
assertEqual(monitor.cleanScale(1.25, 6016, 3384), '1.33', 'monitor matches clean physical display scale')
assertEqual(monitor.cleanScale(1.6, 0, 800), '', 'monitor rejects a missing display mode')
assertEqual(
  monitor.matchingScaleIndex(['1', '1.25', '1.6', '2', '3', '4'], 3.2, 1280, 800),
  4,
  'monitor selects an approximated VM scale'
)
assertEqual(
  monitor.matchingScaleIndex(['1', '1.25', '1.6', '2', '3', '4'], 4, 4, 4),
  5,
  'monitor selects an exact preset'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 1280, 800),
  ['1', '1.25', '1.6', '2', '3', '4'],
  'monitor keeps distinct approximated VM scales'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 6016, 3384),
  ['1', '1.25', '1.6', '2', '3', '4'],
  'monitor keeps distinct approximated physical display scales'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 1280, 804),
  ['1', '1.25', '2', '4'],
  'monitor collapses presets with duplicate effective scales'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 5968, 3230),
  ['1', '2'],
  'monitor hides presets the current mode cannot reach'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 0, 0),
  ['1', '1.25', '1.6', '2', '3', '4'],
  'monitor keeps presets until display dimensions are known'
)

// The panel re-reads state constantly; replacing the list rebuilds every row,
// which destroys the switch under the pointer mid-click.
const twoDisplays = [
  { name: 'eDP-1', enabled: true, focused: false, width: 2880, height: 1920, scale: 2 },
  { name: 'DP-7', enabled: true, focused: true, width: 5120, height: 2880, scale: 2 }
]
assertEqual(monitor.displaysEqual(twoDisplays, twoDisplays.slice()), true, 'an unchanged read compares equal')
assertEqual(
  monitor.displaysEqual(twoDisplays, [{ ...twoDisplays[0], enabled: false }, twoDisplays[1]]),
  false,
  'a display switching off compares different'
)
assertEqual(
  monitor.displaysEqual(twoDisplays, [{ ...twoDisplays[0], focused: true }, twoDisplays[1]]),
  false,
  'focus moving compares different'
)
assertEqual(
  monitor.displaysEqual(twoDisplays, [{ ...twoDisplays[0], scale: 1 }, twoDisplays[1]]),
  false,
  'a scale change compares different'
)
assertEqual(monitor.displaysEqual(twoDisplays, [twoDisplays[0]]), false, 'a display disappearing compares different')

assertEqual(monitor.brightnessName(96), 'Sun blast', 'monitor names very bright displays')
assertEqual(monitor.brightnessName(12), 'Candlelit', 'monitor names dim displays')

assertDeepEqual(
  monitor.parseDisplays(JSON.stringify([
    { name: 'eDP-1', enabled: true, focused: false, width: 1920, height: 1080 },
    { name: 'HDMI-A-1', enabled: false, focused: false, width: 0, height: 0 },
    { name: 'DP-1', enabled: true, focused: true, width: 1280, height: 800 }
  ])),
  {
    displays: [
      { name: 'eDP-1', enabled: true, focused: false, width: 1920, height: 1080 },
      { name: 'HDMI-A-1', enabled: false, focused: false, width: 0, height: 0 },
      { name: 'DP-1', enabled: true, focused: true, width: 1280, height: 800 }
    ],
    enabledDisplayCount: 2
  },
  'monitor parses display state'
)

assertDeepEqual(monitor.parseDisplays('{'), { displays: [], enabledDisplayCount: 0 }, 'monitor handles invalid display JSON')
JS

# A mirroring display is enabled in `monitors all` but absent from plain
# `monitors`, and the scaling command refuses it. The panel has to be able to
# tell it apart from a display that is simply switched off, or it offers scale
# controls whose every press is silently rejected.
run_node_test <<'JS'
const monitor = requireFromRoot('shell/plugins/panels/monitor/Model.js')

const parsed = monitor.parseDisplays(JSON.stringify([
  { name: 'eDP-1', enabled: true, driven: true, focused: true, width: 2880, height: 1920, scale: 2 },
  { name: 'DP-7', enabled: true, driven: false, focused: false, width: 5120, height: 2880, scale: 2 }
]))

assertEqual(parsed.displays.length, 2, 'monitor lists a mirroring display')
assertEqual(parsed.displays[1].driven, false, 'monitor carries through a display it is not driving')
assertEqual(parsed.displays[1].enabled, true, 'monitor keeps a mirroring display enabled')

const same = JSON.parse(JSON.stringify(parsed.displays))
same[1].driven = true
assertEqual(
  monitor.displaysEqual(parsed.displays, same),
  false,
  'monitor treats a change in driven as a change'
)
JS
pass "monitor distinguishes a display it is not driving from a disabled one"
