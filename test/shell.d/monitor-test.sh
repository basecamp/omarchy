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

// ---------- Display-panel arrangement additions ----------

assertDeepEqual(monitor.parseMode('3440x1440@59.97'), { width: 3440, height: 1440, refresh: 59.97, raw: '3440x1440@59.97' }, 'monitor parses a mode string')
assertDeepEqual(monitor.parseMode('2560x1440@60Hz'), { width: 2560, height: 1440, refresh: 60, raw: '2560x1440@60Hz' }, 'monitor parses a mode string with an Hz suffix')
assertDeepEqual(monitor.parseMode('preferred'), { width: 0, height: 0, refresh: 0, raw: 'preferred' }, 'monitor treats a non-numeric mode as unparsed')

assertDeepEqual(monitor.rotateDimensions(1920, 1080, 0), { width: 1920, height: 1080 }, 'monitor keeps dimensions for transform 0')
assertDeepEqual(monitor.rotateDimensions(1920, 1080, 1), { width: 1080, height: 1920 }, 'monitor swaps dimensions for a 90-degree transform')
assertDeepEqual(monitor.rotateDimensions(1920, 1080, 2), { width: 1920, height: 1080 }, 'monitor keeps dimensions for a 180-degree transform')
assertDeepEqual(monitor.rotateDimensions(1920, 1080, 3), { width: 1080, height: 1920 }, 'monitor swaps dimensions for a 270-degree transform')

assertEqual(
  monitor.monitorIdentity({ name: 'DVI-I-1', description: 'LG Electronics LG ULTRAGEAR 101NTKF0A749' }),
  'desc:LG Electronics LG ULTRAGEAR 101NTKF0A749',
  'monitor keys identity off description when one is available'
)
assertEqual(
  monitor.monitorIdentity({ name: 'eDP-1', description: '' }),
  'eDP-1',
  'monitor falls back to connector name without a description'
)

const extended = monitor.parseExtendedDisplays(JSON.stringify([
  {
    name: 'DVI-I-1', description: 'LG Electronics LG ULTRAGEAR+ 510RMLM6U896', serial: 'LG Electronics',
    enabled: true, focused: false, x: 0, y: 0, width: 3440, height: 1440, scale: 1.25, transform: 0,
    currentMode: '3440x1440@59.97', availableModes: ['3440x1440@59.97', '2560x1080@59.97']
  },
  {
    name: 'eDP-1', description: '', serial: '',
    enabled: false, focused: true, x: 626, y: 1152, width: 3000, height: 2000, scale: 2, transform: 0,
    currentMode: '3000x2000@59.98', availableModes: []
  }
]))
assertEqual(extended.enabledDisplayCount, 1, 'monitor counts only enabled displays in the extended shape')
assertEqual(extended.displays.length, 2, 'monitor parses every extended display entry')
assertEqual(extended.displays[1].description, '', 'monitor tolerates a missing description in the extended shape')
assertDeepEqual(monitor.parseExtendedDisplays('not json'), { displays: [], enabledDisplayCount: 0 }, 'monitor handles invalid extended display JSON')

const twoMonitors = [
  { name: 'DVI-I-1', description: 'LG Electronics LG ULTRAGEAR+ 510RMLM6U896', enabled: true, x: 0, y: 0, width: 3440, height: 1440, scale: 1.25, transform: 0 },
  { name: 'eDP-1', description: '', enabled: true, x: 2752, y: 0, width: 3000, height: 2000, scale: 2, transform: 3 }
]
const bounds = monitor.arrangementBounds(twoMonitors)
assertEqual(bounds.x, 0, 'monitor arrangement bounds start at the leftmost enabled monitor')
assertEqual(Math.round(bounds.width), 3752, 'monitor arrangement bounds span every enabled monitor, rotation included')

const boundsSkipsDisabled = monitor.arrangementBounds([
  { name: 'DP-1', description: '', enabled: false, x: -5000, y: -5000, width: 1920, height: 1080, scale: 1, transform: 0 },
  { name: 'eDP-1', description: '', enabled: true, x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 }
])
assertEqual(boundsSkipsDisabled.x, 0, 'monitor arrangement bounds ignore disabled monitors')

const scaled = monitor.scaleArrangement(twoMonitors, bounds, 200, 100, 4, 'eDP-1')
assertEqual(scaled.length, 2, 'monitor scales every monitor into canvas tiles')
assert(scaled[1].selected, 'monitor marks the selected tile by identity')
assert(!scaled[0].selected, 'monitor leaves unselected tiles unmarked')
assertEqual(scaled[0].identity, 'desc:LG Electronics LG ULTRAGEAR+ 510RMLM6U896', 'monitor tiles carry description-based identity')
// Centered, not pinned to the corner: some positive margin on the leading edge
// whenever the arrangement doesn't already fill the canvas.
assert(scaled[0].x >= 0, 'monitor centers the arrangement horizontally rather than pinning it to the corner')

const padded = monitor.paddedBounds({ x: 0, y: 10, width: 100, height: 50 }, 0.2)
assertDeepEqual(padded, { x: -20, y: 0, width: 140, height: 70 }, 'monitor pads arrangement bounds without moving with a dragged tile')
assertEqual(monitor.logicalFromCanvas(25, 0.5), 50, 'monitor converts canvas drag distance back to logical monitor coordinates')

assertDeepEqual(monitor.compactModes(['a', 'b', 'a', 'c'], 'c', 6), ['c', 'a', 'b'], 'monitor de-duplicates modes and leads with the current one')
assertDeepEqual(monitor.compactModes(['a', 'b', 'c', 'd'], '', 2), ['a', 'b'], 'monitor caps the compacted mode list to the limit')

assertDeepEqual(
  monitor.modeOptions(['3440x1440@59.97', '2560x1080@59.97'], '3440x1440@59.97', 6),
  [
    { label: '3440×1440 60Hz', value: '3440x1440@59.97' },
    { label: '2560×1080 60Hz', value: '2560x1080@59.97' }
  ],
  'monitor formats mode options with rounded refresh rates'
)

const liveByIdentity = { 'eDP-1': { enabled: true, currentMode: '3000x2000@59.98', scale: 2, transform: 0, x: 626, y: 1152 } }
assertDeepEqual(
  monitor.diffPending(liveByIdentity, { 'eDP-1': { scale: 2 } }),
  {},
  'monitor drops a pending value that already matches live state'
)
assertDeepEqual(
  monitor.diffPending(liveByIdentity, { 'eDP-1': { scale: 1.25, transform: 1 } }),
  { 'eDP-1': { scale: 1.25, transform: 1 } },
  'monitor keeps pending values that actually differ from live state'
)
assert(!monitor.isDirty({}), 'monitor reports clean with no pending diff')
assert(monitor.isDirty({ 'eDP-1': { scale: 1.25 } }), 'monitor reports dirty with a pending diff')

const liveDisplays = [
  { name: 'DVI-I-1', description: 'LG Electronics LG ULTRAGEAR+ 510RMLM6U896', enabled: true, currentMode: '3440x1440@59.97', x: 0, y: 0, scale: 1.25, transform: 0 },
  { name: 'eDP-1', description: '', enabled: true, currentMode: '3000x2000@59.98', x: 626, y: 1152, scale: 2, transform: 0 }
]
assertDeepEqual(
  monitor.buildArrangeLayout(liveDisplays, {}),
  [
    { identity: 'desc:LG Electronics LG ULTRAGEAR+ 510RMLM6U896', mode: '3440x1440@59.97', x: 0, y: 0, scale: 1.25, transform: 0, enabled: true },
    { identity: 'eDP-1', mode: '3000x2000@59.98', x: 626, y: 1152, scale: 2, transform: 0, enabled: true }
  ],
  'monitor builds an arrange layout matching live state with no pending edits'
)
assertDeepEqual(
  monitor.buildArrangeLayout(liveDisplays, { 'eDP-1': { transform: 3, scale: 1.6 } }),
  [
    { identity: 'desc:LG Electronics LG ULTRAGEAR+ 510RMLM6U896', mode: '3440x1440@59.97', x: 0, y: 0, scale: 1.25, transform: 0, enabled: true },
    { identity: 'eDP-1', mode: '3000x2000@59.98', x: 626, y: 1152, scale: 1.6, transform: 3, enabled: true }
  ],
  'monitor overlays pending edits onto the live layout by identity'
)

assertDeepEqual(monitor.parseArrangeResult('{"success":true,"message":"applied 2 monitor(s)"}'), { success: true, message: 'applied 2 monitor(s)' }, 'monitor parses a successful arrange result')
assertDeepEqual(monitor.parseArrangeResult('not json'), { success: false, message: 'invalid backend response' }, 'monitor treats an unparsable arrange result as a failure')
assertDeepEqual(monitor.parseArrangeResult(''), { success: false, message: '' }, 'monitor treats an empty arrange result as an unsuccessful, message-less result')
JS
