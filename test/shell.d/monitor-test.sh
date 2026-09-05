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

assertEqual(
  monitor.displayToggleSpec('DP-1', false),
  'hl.monitor({ output = "DP-1", disabled = false, mode = "preferred", position = "auto", scale = "auto" })',
  'monitor enables a display through the Lua config API'
)
assertEqual(
  monitor.displayToggleSpec('DP-1', true),
  'hl.monitor({ output = "DP-1", disabled = true })',
  'monitor disables a display through the Lua config API'
)
assertEqual(monitor.displayToggleSpec('', false), '', 'monitor ignores a display with no name')

assertDeepEqual(
  monitor.displayToggleCommand('DP-2', true, 'eDP-1'),
  ['hyprctl', 'eval', 'hl.monitor({ output = "DP-2", disabled = true })'],
  'monitor changes an external display with a direct Lua call'
)
assertDeepEqual(
  monitor.displayToggleCommand('eDP-1', true, 'eDP-1'),
  ['omarchy-hyprland-monitor-internal', 'off'],
  'monitor disables the built-in panel through the command that owns it'
)
assertDeepEqual(
  monitor.displayToggleCommand('eDP-1', false, 'eDP-1'),
  ['omarchy-hyprland-monitor-internal', 'on'],
  'monitor enables the built-in panel through the command that owns it'
)
assertDeepEqual(
  monitor.displayToggleCommand('LVDS-1', true, 'LVDS-1'),
  ['omarchy-hyprland-monitor-internal', 'off'],
  'monitor recognises a built-in panel that is not named eDP'
)
assertDeepEqual(
  monitor.displayToggleCommand('DP-2', true, ''),
  ['hyprctl', 'eval', 'hl.monitor({ output = "DP-2", disabled = true })'],
  'monitor takes the direct call where there is no built-in panel'
)
assertEqual(
  monitor.displayToggleCommand('', true, 'eDP-1'),
  null,
  'monitor names no command for a display with no name'
)
assertEqual(monitor.quoteLua('DP"1'), '"DP\\"1"', 'monitor escapes a quote in a display name')
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
