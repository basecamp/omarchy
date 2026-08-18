#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# Feed the panel what the capabilities command really prints, rather than a
# hand-written imitation of it. A connector name that cannot exist keeps the
# output identical on every machine while still exercising the real code path.
OMARCHY_TEST_CAPABILITIES_JSON=$("$ROOT/bin/omarchy-hyprland-monitor-capabilities" OMARCHY-TEST-0)
export OMARCHY_TEST_CAPABILITIES_JSON

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

// ---- Rotation ----
assertEqual(monitor.transformDegrees(0), 0, 'monitor reads an unrotated transform')
assertEqual(monitor.transformDegrees(1), 90, 'monitor reads a quarter-turn transform')
assertEqual(monitor.transformDegrees(3), 270, 'monitor reads a three-quarter-turn transform')
// 4-7 are the mirrored repeats of 0-3, so the angle is the transform mod 4.
assertEqual(monitor.transformDegrees(5), 90, 'monitor reads the angle of a mirrored transform')
assertEqual(monitor.transformDegrees('nope'), 0, 'monitor rejects an invalid transform')

// ---- SDR luminance ----
// The ceiling is the sustained full-field luminance, not the peak: peak applies
// to small highlights, and mapping SDR white there makes a white window dim as
// the panel's brightness limiter pulls power back.
assertDeepEqual(monitor.sdrLuminanceRange(277), { minimum: 40, maximum: 277 }, 'monitor derives the SDR range from full-field luminance')
assertDeepEqual(monitor.sdrLuminanceRange(0), { minimum: 40, maximum: 400 }, 'monitor falls back to a default SDR range')
// The range never narrows below 100 nits, because a narrower one cannot survive
// a round trip through whole percentages and the slider drifts a notch on its own.
assertDeepEqual(monitor.sdrLuminanceRange(50), { minimum: 40, maximum: 140 }, 'monitor keeps a usable SDR range on a dim display')

assertEqual(monitor.clampSdrLuminance(250, 277), 250, 'monitor keeps an in-range SDR luminance')
assertEqual(monitor.clampSdrLuminance(900, 277), 277, 'monitor clamps SDR luminance to full-field luminance')
assertEqual(monitor.clampSdrLuminance(1, 277), 40, 'monitor clamps SDR luminance to the floor')
assertEqual(monitor.clampSdrLuminance('nope', 277), 40, 'monitor rejects an invalid SDR luminance')

// ---- HDR capability ----
assertDeepEqual(
  monitor.parseCapabilities(JSON.stringify({
    name: 'DP-1', hdr: true, max_luminance: 993, max_avg_luminance: 277, min_luminance: 0.001
  })),
  { name: 'DP-1', hdr: true, maxLuminance: 993, maxAvgLuminance: 277, minLuminance: 0.001 },
  'monitor parses HDR capabilities'
)
assertDeepEqual(
  monitor.parseCapabilities(JSON.stringify({ name: 'DP-3', hdr: false, reason: 'no-pq-eotf' })),
  { name: 'DP-3', hdr: false, maxLuminance: 0, maxAvgLuminance: 0, minLuminance: 0 },
  'monitor parses a display without HDR'
)
assertDeepEqual(
  monitor.parseCapabilities('{'),
  { name: '', hdr: false, maxLuminance: 0, maxAvgLuminance: 0, minLuminance: 0 },
  'monitor handles invalid capability JSON'
)

// The slider stays a percentage in both modes, so an SDR luminance converts to
// its position within the range the display can hold, and back.
assertEqual(monitor.sdrLuminanceToPercent(250, 277), 89, 'monitor expresses SDR luminance as a percentage')
assertEqual(monitor.sdrLuminanceToPercent(40, 277), 0, 'monitor puts the SDR floor at zero percent')
assertEqual(monitor.sdrLuminanceToPercent(277, 277), 100, 'monitor puts the SDR ceiling at full percent')
assertEqual(monitor.sdrPercentToLuminance(100, 277), 277, 'monitor maps full percent to the SDR ceiling')
assertEqual(monitor.sdrPercentToLuminance(0, 277), 40, 'monitor maps zero percent to the SDR floor')
assertEqual(monitor.sdrPercentToLuminance(150, 277), 277, 'monitor clamps an out-of-range percentage')
assertEqual(monitor.sdrPercentToLuminance('nope', 277), 40, 'monitor rejects an invalid percentage')
// Round-tripping must land back on the same percentage the slider showed.
assertEqual(monitor.sdrLuminanceToPercent(monitor.sdrPercentToLuminance(60, 277), 277), 60, 'monitor round-trips a percentage through luminance')

// ---------------------------------------------------------------------------
// Properties. The cases above pin specific values; these assert the invariants
// the panel actually depends on, so a change of internal representation stays
// free but a change of behaviour does not. Each property is one assertion over
// a whole input space, reporting the offending inputs rather than a bare false.
// ---------------------------------------------------------------------------

function assertHolds(violations, description) {
  assert(
    violations.length === 0,
    description,
    violations.length + ' violation(s), first few: ' + JSON.stringify(violations.slice(0, 5))
  )
}

var everyTransform = [0, 1, 2, 3, 4, 5, 6, 7]

// ---- Rotation / transform mapping ----

// Every Hyprland transform is one of the four quarter turns, mirrored or not.
// The panel only offers degrees, so an angle outside that set is one it can
// neither render nor undo.
assertHolds(
  everyTransform.filter(function(t) {
    return monitor.rotationDegrees.indexOf(monitor.transformDegrees(t)) < 0
  }),
  'monitor reports every transform as one of the offered angles'
)

// Hyprland reports transforms as numbers but the panel reads them back out of
// JSON, where a string is just as likely; the two readings must agree.
assertEqual(monitor.transformDegrees('2'), 180, 'monitor reads a transform given as a string')

// Garbage must degrade to "unrotated" rather than to NaN, which would
// otherwise be written straight into monitors.lua.
assertHolds(
  ['nope', null, undefined, NaN, -1, -8, Infinity].filter(function(bad) {
    return monitor.transformDegrees(bad) !== 0
  }).map(String),
  'monitor reads an unusable transform as unrotated'
)

// ---- SDR luminance range, clamp and percent round-trip ----

// 0 and the low ceilings matter because a panel that advertises a modest
// desired frame-average luminance is common; 4000 covers the other end.
var luminanceCeilings = [0, 50, 100, 120, 140, 200, 277, 400, 600, 1000, 4000]
var unusableCeilings = [0, -100, 'nope', null, undefined, NaN, Infinity]

// A collapsed or inverted range would make the slider unusable and make the
// percent conversions divide by zero. A non-HDR display carries no full-field
// luminance in its EDID at all, so the unusable ceilings are the normal case.
assertHolds(
  luminanceCeilings.concat(unusableCeilings).filter(function(ceiling) {
    var range = monitor.sdrLuminanceRange(ceiling)
    return !isFinite(range.minimum) || !isFinite(range.maximum) || range.maximum <= range.minimum
  }).map(String),
  'monitor derives a usable SDR range from any ceiling'
)

// Clamping is what stops a stale or hand-edited sdr_max_luminance being handed
// back to the compositor unchanged; and clamping an already-clamped value must
// not move it again, or the stored luminance drifts every time the panel opens.
var clampViolations = []
luminanceCeilings.forEach(function(ceiling) {
  var range = monitor.sdrLuminanceRange(ceiling)
  ;[-1000, 0, 1, 39, 40, 100, 250, 5000, 'nope', NaN, Infinity, null].forEach(function(value) {
    var clamped = monitor.clampSdrLuminance(value, ceiling)
    if (clamped < range.minimum || clamped > range.maximum) {
      clampViolations.push(String(value) + ' @ ' + ceiling + ' -> ' + clamped + ' (outside range)')
    } else if (monitor.clampSdrLuminance(clamped, ceiling) !== clamped) {
      clampViolations.push(String(value) + ' @ ' + ceiling + ' -> ' + clamped + ' (not settled)')
    }
  })
})
assertHolds(clampViolations, 'monitor clamps any SDR luminance into the range and leaves it there')

// The slider position must always be a whole percentage, whatever luminance it
// is handed -- including one carried over from a display with another ceiling.
var percentViolations = []
luminanceCeilings.forEach(function(ceiling) {
  ;[-1000, 0, 40, 120, 5000, 'nope', NaN, null].forEach(function(value) {
    var percent = monitor.sdrLuminanceToPercent(value, ceiling)
    if (!Number.isInteger(percent) || percent < 0 || percent > 100) {
      percentViolations.push(String(value) + ' @ ' + ceiling + ' -> ' + percent)
    }
  })
})
assertHolds(percentViolations, 'monitor expresses any SDR luminance as a whole percentage')

// And the reverse: any percentage must land inside the range the display can
// hold, so the value written to monitors.lua is always legal.
var toLuminanceViolations = []
luminanceCeilings.forEach(function(ceiling) {
  var range = monitor.sdrLuminanceRange(ceiling)
  ;[-50, 0, 33, 50, 100, 1000, 'nope', NaN, null].forEach(function(value) {
    var nits = monitor.sdrPercentToLuminance(value, ceiling)
    if (!(nits >= range.minimum && nits <= range.maximum)) {
      toLuminanceViolations.push(String(value) + ' @ ' + ceiling + ' -> ' + nits)
    }
  })
})
assertHolds(toLuminanceViolations, 'monitor maps any percentage into the SDR range')

// Dragging the slider right must never lower the luminance.
var monotonicViolations = []
luminanceCeilings.forEach(function(ceiling) {
  var previous = -Infinity
  for (var p = 0; p <= 100; p++) {
    var nits = monitor.sdrPercentToLuminance(p, ceiling)
    if (nits < previous) monotonicViolations.push(p + '% @ ' + ceiling + ' -> ' + nits + ' after ' + previous)
    previous = nits
  }
})
assertHolds(monotonicViolations, 'monitor raises SDR luminance monotonically with the slider')

// The ends of the slider must reach the ends of the range exactly, or the user
// can never pick the dimmest or brightest SDR white the panel supports.
var endpointViolations = []
luminanceCeilings.forEach(function(ceiling) {
  var range = monitor.sdrLuminanceRange(ceiling)
  if (monitor.sdrPercentToLuminance(0, ceiling) !== range.minimum) endpointViolations.push('0% @ ' + ceiling)
  if (monitor.sdrPercentToLuminance(100, ceiling) !== range.maximum) endpointViolations.push('100% @ ' + ceiling)
  if (monitor.sdrLuminanceToPercent(range.minimum, ceiling) !== 0) endpointViolations.push('floor @ ' + ceiling)
  if (monitor.sdrLuminanceToPercent(range.maximum, ceiling) !== 100) endpointViolations.push('ceiling @ ' + ceiling)
})
assertHolds(endpointViolations, 'monitor reaches both ends of the SDR range from both directions')

// The same in the other direction: a luminance already in monitors.lua must
// survive being shown as a percentage and written back, to within one step of
// the slider it is displayed on.
var storedViolations = []
luminanceCeilings.forEach(function(ceiling) {
  var range = monitor.sdrLuminanceRange(ceiling)
  var step = Math.ceil((range.maximum - range.minimum) / 100)
  for (var nits = range.minimum; nits <= range.maximum; nits++) {
    var again = monitor.sdrPercentToLuminance(monitor.sdrLuminanceToPercent(nits, ceiling), ceiling)
    if (Math.abs(again - nits) > step) storedViolations.push(nits + ' @ ' + ceiling + ' -> ' + again)
  }
})
assertHolds(storedViolations, 'monitor keeps a stored SDR luminance within one slider step')

// ---- HDR capability parsing ----

// The panel is handed whatever omarchy-hyprland-monitor-capabilities printed, so
// the parser must always produce the same five-field shape with usable types. A
// missing field has to read as absent, never as NaN or undefined, because the
// luminances go on to feed sdrLuminanceRange.
function capabilityShapeProblem(parsed) {
  if (parsed === null || typeof parsed !== 'object') return 'not an object'
  if (typeof parsed.name !== 'string') return 'name is ' + typeof parsed.name
  if (typeof parsed.hdr !== 'boolean') return 'hdr is ' + typeof parsed.hdr
  if (!isFinite(parsed.maxLuminance)) return 'maxLuminance is ' + parsed.maxLuminance
  if (!isFinite(parsed.maxAvgLuminance)) return 'maxAvgLuminance is ' + parsed.maxAvgLuminance
  if (!isFinite(parsed.minLuminance)) return 'minLuminance is ' + parsed.minLuminance
  return ''
}

var capabilityInputs = [
  '', null, undefined, '{', '[]', '[1,2]', 'null', 'true', '42', '"text"', '{}',
  JSON.stringify({ name: 'DP-1', hdr: false, reason: 'no-edid' }),
  JSON.stringify({ name: 'DP-1', hdr: false, reason: 'no-pq-eotf' }),
  JSON.stringify({ name: 'DP-1', hdr: true, max_luminance: 'x', max_avg_luminance: null }),
  JSON.stringify({ name: 'DP-1', hdr: true, max_luminance: null, max_avg_luminance: null, min_luminance: null }),
  JSON.stringify({ name: 'DP-1', hdr: true, max_luminance: 993, max_avg_luminance: 277, min_luminance: 0.001 })
]
assertHolds(
  capabilityInputs.map(function(raw) {
    var problem = capabilityShapeProblem(monitor.parseCapabilities(raw))
    return problem ? JSON.stringify(raw) + ': ' + problem : ''
  }).filter(Boolean),
  'monitor parses any capabilities output into the panel shape'
)

// Whatever came back, it must be safe to feed straight into the SDR range: a
// non-HDR reply carries no luminances at all and is the common case.
assertHolds(
  capabilityInputs.filter(function(raw) {
    var range = monitor.sdrLuminanceRange(monitor.parseCapabilities(raw).maxAvgLuminance)
    return range.maximum <= range.minimum
  }).map(function(raw) { return JSON.stringify(raw) }),
  'monitor derives a usable SDR range from any parsed capabilities'
)

// HDR must be enabled only on an explicit true. A truthy-but-not-true value
// (the string "true" from a shell, a 1) would otherwise switch the compositor
// into HDR on a display that never claimed it.
assertHolds(
  ['true', 1, 'yes', {}, [], 'TRUE', 'false'].filter(function(truthy) {
    return monitor.parseCapabilities(JSON.stringify({ name: 'DP-1', hdr: truthy })).hdr !== false
  }).map(function(v) { return JSON.stringify(v) }),
  'monitor refuses HDR for any non-boolean hdr value'
)
assertEqual(monitor.parseCapabilities(JSON.stringify({ hdr: true })).hdr, true, 'monitor accepts an explicit HDR claim')

// min_luminance is a fraction of a nit on real panels; rounding it away would
// lose the whole value.
assertEqual(
  monitor.parseCapabilities(JSON.stringify({ min_luminance: 0.0005 })).minLuminance,
  0.0005,
  'monitor keeps a sub-nit minimum luminance'
)

// The real command's output must be parseable by the panel. This is the
// contract between bin/omarchy-hyprland-monitor-capabilities and Model.js, and
// nothing else checks that the two still agree.
var live = process.env.OMARCHY_TEST_CAPABILITIES_JSON || ''
assertEqual(
  capabilityShapeProblem(monitor.parseCapabilities(live)),
  '',
  'monitor parses what omarchy-hyprland-monitor-capabilities actually prints'
)
assertEqual(
  monitor.parseCapabilities(live).name,
  JSON.parse(live).name,
  'monitor keeps the display name the capabilities command reported'
)

// ---- Scale helpers reached with an unusable mode ----

var presets = ['1', '1.25', '1.6', '2', '3', '4']

// availableScales must only ever return presets it was given, never invent or
// duplicate one, and never return nothing.
var realModes = [[1280, 800], [1280, 804], [5968, 3230], [6016, 3384], [3840, 2160], [2256, 1504], [2560, 1440]]
assertHolds(
  realModes.filter(function(mode) {
    var offered = monitor.availableScales(presets, mode[0], mode[1])
    return offered.length === 0
      || !offered.every(function(s) { return presets.indexOf(s) >= 0 })
      || new Set(offered).size !== offered.length
  }).map(function(mode) { return mode.join('x') }),
  'monitor offers a non-empty subset of the presets for every real mode'
)

// Every offered preset must be selectable: the panel highlights the current
// scale by looking it up again, so a button that can never match is dead.
var unhighlightable = []
realModes.forEach(function(mode) {
  monitor.availableScales(presets, mode[0], mode[1]).forEach(function(s) {
    var effective = monitor.cleanScale(s, mode[0], mode[1])
    var offered = monitor.availableScales(presets, mode[0], mode[1])
    if (monitor.matchingScaleIndex(offered, Number(effective), mode[0], mode[1]) < 0) {
      unhighlightable.push(s + ' @ ' + mode.join('x') + ' (effective ' + effective + ')')
    }
  })
})
assertHolds(unhighlightable, 'monitor can highlight every scale it offers')

// ---------------------------------------------------------------------------
// Regressions for defects confirmed against this Model.js. Kept last so a
// still-unfixed defect does not mask the coverage above.
// ---------------------------------------------------------------------------

// Percent -> luminance -> percent must be stable across the whole slider for
// every plausible ceiling: Panel.qml stores the luminance the slider produced
// and reads it straight back as a percentage, so any drift makes the brightness
// knob jump a notch on its own after the user lets go.
var roundTripViolations = []
luminanceCeilings.forEach(function(ceiling) {
  for (var p = 0; p <= 100; p++) {
    var nits = monitor.sdrPercentToLuminance(p, ceiling)
    var back = monitor.sdrLuminanceToPercent(nits, ceiling)
    if (back !== p) roundTripViolations.push(p + '% @ ' + ceiling + ' -> ' + nits + ' nits -> ' + back + '%')
  }
})
assertHolds(roundTripViolations, 'monitor round-trips every percentage through SDR luminance')

// Panel.qml feeds display.width/height straight from parsed JSON, so a display
// whose mode has not been reported yet arrives as undefined or as a string.
// That must fall through to the full preset list the way width 0 already does;
// collapsing to a single button leaves the user unable to change scale at all.
assertHolds(
  [[undefined, undefined], ['a', 'b'], [NaN, NaN], [null, undefined], ['', ''], [0, 0], [-1, -1]].filter(function(mode) {
    return JSON.stringify(monitor.availableScales(presets, mode[0], mode[1])) !== JSON.stringify(presets)
  }).map(function(mode) {
    return JSON.stringify(mode) + ' -> ' + JSON.stringify(monitor.availableScales(presets, mode[0], mode[1]))
  }),
  'monitor keeps every scale preset when the mode is unusable'
)

// cleanScale snaps a requested scale to one the mode can actually render, so
// its own output must already be snapped -- otherwise re-saving a display
// nobody touched changes its scale.
//
// Scoped to the presets the panel actually offers. cleanScale reports through
// normalizeScale, which rounds to two decimals, so an arbitrary scale whose
// clean value needs three (1920x1080 at 1.7 cleans to 1.875, reported as 1.88)
// does not survive a second pass. That rounding is pre-existing and is what
// matchingScaleIndex compares against, so it is left alone; the panel only ever
// feeds cleanScale these presets, and every one of them is a fixed point.
var unsettled = []
realModes.forEach(function(mode) {
  presets.forEach(function(preset) {
    var once = monitor.cleanScale(preset, mode[0], mode[1])
    var twice = monitor.cleanScale(once, mode[0], mode[1])
    if (once !== twice) unsettled.push(mode.join('x') + ' ' + preset + ': ' + once + ' -> ' + twice)
  })
})
assertHolds(unsettled, 'monitor settles every offered preset after one pass')
JS
