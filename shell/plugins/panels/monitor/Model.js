function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  // isFinite as well as the range check: NaN fails every comparison, so a
  // non-numeric mode would slip through and collapse every preset onto one key.
  if (!Array.isArray(scales) || !isFinite(Number(width)) || !isFinite(Number(height))
      || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

// Hyprland's `transform` is 0-7: 0-3 are the plain rotations, 4-7 repeat them
// mirrored. The panel offers degrees and hands them to the rotate command,
// which owns the mapping back to a transform and the mirrored half with it.
// Declared under the name QML uses. A .js module only exposes its top-level
// declarations, so an alias that exists solely in module.exports would read as
// undefined from QML while still passing the Node tests.
var rotationDegrees = [0, 90, 180, 270]

function transformDegrees(transform) {
  var value = Number(transform)
  if (!isFinite(value) || value < 0) return 0
  return (Math.floor(value) % 4) * 90
}

// The usable range for SDR white inside the HDR volume. The top is the
// display's sustained full-field luminance rather than its peak: peak applies
// to small highlights, and mapping SDR white there makes a full white window
// dim as the panel's automatic brightness limiter pulls power back.
function sdrLuminanceRange(maxAvgLuminance) {
  var ceiling = Math.round(Number(maxAvgLuminance))
  if (!isFinite(ceiling) || ceiling <= 0) ceiling = 400
  // At least 100 nits wide: a narrower range cannot survive a round trip
  // through whole percentages, and the slider would jump a notch on its own.
  return { minimum: 40, maximum: Math.max(140, ceiling) }
}

function clampSdrLuminance(value, maxAvgLuminance) {
  var range = sdrLuminanceRange(maxAvgLuminance)
  var nits = Math.round(Number(value))
  if (!isFinite(nits)) return range.minimum
  return Math.max(range.minimum, Math.min(range.maximum, nits))
}

// The panel shows one percentage whichever knob the brightness slider is on, so
// an SDR luminance is expressed as its position within the range the display
// can hold, and back again.
function sdrLuminanceToPercent(nits, maxAvgLuminance) {
  var range = sdrLuminanceRange(maxAvgLuminance)
  var span = Math.max(1, range.maximum - range.minimum)
  var value = Number(nits)
  if (!isFinite(value)) return 0
  return Math.max(0, Math.min(100, Math.round(((value - range.minimum) / span) * 100)))
}

function sdrPercentToLuminance(percent, maxAvgLuminance) {
  var range = sdrLuminanceRange(maxAvgLuminance)
  var span = range.maximum - range.minimum
  var value = Number(percent)
  if (!isFinite(value)) return range.minimum
  var clamped = Math.max(0, Math.min(100, value))
  return Math.round(range.minimum + (clamped / 100) * span)
}

function parseCapabilities(raw) {
  var parsed = {}
  try {
    parsed = raw ? JSON.parse(String(raw)) : {}
  } catch (e) {
    parsed = {}
  }
  if (!parsed || typeof parsed !== "object") parsed = {}
  return {
    name: parsed.name || "",
    hdr: parsed.hdr === true,
    maxLuminance: Number(parsed.max_luminance) || 0,
    maxAvgLuminance: Number(parsed.max_avg_luminance) || 0,
    minLuminance: Number(parsed.min_luminance) || 0
  }
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays,
    rotationDegrees: rotationDegrees,
    transformDegrees: transformDegrees,
    sdrLuminanceRange: sdrLuminanceRange,
    clampSdrLuminance: clampSdrLuminance,
    sdrLuminanceToPercent: sdrLuminanceToPercent,
    sdrPercentToLuminance: sdrPercentToLuminance,
    parseCapabilities: parseCapabilities
  }
}
