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

assertDeepEqual(
  monitor.parseTextSizeStatus('text size: 12 px\ngtk text-scaling-factor: 1.25\nterminal font: 10.5 pt\n'),
  { gtkPx: 15, termPt: 10.5 },
  'monitor converts gtk factor to px and passes terminal points through'
)
assertDeepEqual(
  monitor.parseTextSizeStatus('text size: 12 px\ngtk text-scaling-factor: 1\nterminal font: 11.0 pt\n'),
  { gtkPx: 12, termPt: 11 },
  'monitor reads a kitty-style decimal terminal point size'
)
assertDeepEqual(
  monitor.parseTextSizeStatus('text size: 12 px\ngtk text-scaling-factor: 1\nterminal font: n/a pt\n'),
  { gtkPx: 12, termPt: 0 },
  'monitor reports an undescribed terminal font as unavailable'
)
assertDeepEqual(
  monitor.parseTextSizeStatus('text size: 12 px\ngtk text-scaling-factor: 1\nterminal font: 10..5 pt\n'),
  { gtkPx: 12, termPt: 0 },
  'monitor reports a malformed terminal point size as unavailable'
)
assertDeepEqual(
  monitor.parseTextSizeStatus(''),
  { gtkPx: 0, termPt: 0 },
  'monitor reports empty text size status as unavailable'
)
assertDeepEqual(
  monitor.parseTextSizeStatus('command not found'),
  { gtkPx: 0, termPt: 0 },
  'monitor reports malformed text size status as unavailable'
)

assertEqual(monitor.ptToPx(7), 9, 'monitor rounds 7pt down to 9px')
assertEqual(monitor.ptToPx(8), 11, 'monitor rounds 8pt up to 11px')
assertEqual(monitor.ptToPx(9), 12, 'monitor maps the 9pt terminal default onto the 12px anchor')
assertEqual(monitor.ptToPx(11), 15, 'monitor rounds 11pt up to 15px')
assertEqual(monitor.ptToPx(12), 16, 'monitor maps 12pt to 16px')
assertEqual(monitor.ptToPx(14), 19, 'monitor rounds 14pt up to 19px')
assertEqual(monitor.ptToPx(15), 20, 'monitor maps the largest terminal point stop to 20px')
assertEqual(monitor.pxToPt(10), 8, 'monitor rounds 10px up to 8pt')
assertEqual(monitor.pxToPt(14), 11, 'monitor rounds the 14px half-point boundary up to 11pt')
for (let pt = 7; pt <= 15; pt++) {
  assertEqual(monitor.pxToPt(monitor.ptToPx(pt)), pt, `terminal pt ${pt} round-trips through px`)
}
JS
