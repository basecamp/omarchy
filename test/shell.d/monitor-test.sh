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
assertEqual(monitor.cleanScale(1.25, 6016, 3384), '1.18', 'monitor matches clean physical display scale')
assertEqual(monitor.cleanScale(1.6, 0, 800), '', 'monitor rejects a missing display mode')

// Hyprland searches one step up and one step down at each distance from the
// requested scale, so the nearest clean scale below is preferred over a further
// one above. Searching upward only moved these displays to a scale the
// compositor never applies.
assertEqual(monitor.cleanScale(1.25, 1366, 768), '1', 'monitor snaps down when down is nearer')
assertEqual(monitor.cleanScale(1.25, 2256, 1504), '1.18', 'monitor matches a Framework display scale')
assertEqual(monitor.cleanScale(1.6, 3024, 1964), '1.33', 'monitor matches a MacBook display scale')
assertEqual(monitor.cleanScale(1.75, 1920, 1080), '1.67', 'monitor prefers the nearer scale below 1.75')

// Hyprland gives up after 89 steps and falls back to the default scale rather
// than applying something far away, so there is no effective scale to report.
assertEqual(monitor.cleanScale(3, 1366, 768), '', 'monitor reports no scale where Hyprland finds no divisor')
assertEqual(monitor.cleanScale(4, 3456, 2234), '', 'monitor reports no scale for an unreachable request')
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

// The panel and the compositor have to agree on the number, so check against
// Hyprland's own search rather than against a table of remembered answers.
// Transcribed from CMonitor::applyMonitorRule: round to 1/120 units, accept if
// the logical size is whole, otherwise step outward -- up first -- for 89 steps.
function hyprlandScale(scale, width, height) {
  function whole(units) {
    return units > 0 && (width * 120) % units === 0 && (height * 120) % units === 0
  }

  var units = Math.round(scale * 120)
  if (whole(units)) return String(Math.round((units / 120) * 100) / 100)

  for (var step = 1; step < 90; step++) {
    if (whole(units + step)) return String(Math.round(((units + step) / 120) * 100) / 100)
    if (whole(units - step)) return String(Math.round(((units - step) / 120) * 100) / 100)
  }

  return ''
}

var mismatches = []
var checked = 0
var widths = [1280, 1366, 1440, 1600, 1920, 2160, 2256, 2560, 2880, 3024, 3440, 3456, 3840]
var ratios = [9 / 16, 10 / 16, 3 / 4, 2 / 3]
var requests = [1, 1.25, 1.5, 1.6, 1.75, 2, 2.5, 3, 4]
for (var w = 0; w < widths.length; w++) {
  for (var r = 0; r < ratios.length; r++) {
    var height = widths[w] * ratios[r]
    if (height !== Math.round(height)) continue
    for (var q = 0; q < requests.length; q++) {
      checked++
      var mine = monitor.cleanScale(requests[q], widths[w], height)
      var theirs = hyprlandScale(requests[q], widths[w], height)
      if (mine !== theirs)
        mismatches.push(widths[w] + 'x' + height + ' @' + requests[q] + ': ' + mine + ' vs ' + theirs)
    }
  }
}
assert(checked > 100, 'monitor scale sweep covers a useful range of modes')
assert(
  mismatches.length === 0,
  'monitor reports the scale Hyprland applies',
  mismatches.slice(0, 5).join('\n')
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
