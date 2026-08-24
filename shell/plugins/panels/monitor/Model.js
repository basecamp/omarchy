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

// The scale Hyprland will actually apply for a requested one, or "" when it
// would reject the request outright.
//
// Hyprland rounds the request to 1/120 units and, if the logical size is not
// whole, searches outward from there -- one step up, one step down, up to 89
// steps -- taking the first scale that divides the mode evenly, and giving up
// if none does (CMonitor::applyMonitorRule). Searching upward only, and without
// that bound, put the panel on a different number from the compositor: a
// 1366x768 panel asked for 1.25 reads as 2 here while Hyprland applies 1, and a
// 2256x1504 Framework display reads as 1.33 against Hyprland's 1.18.
//
// `logicalSize` is whole exactly when the scale in 1/120 units divides both
// mode dimensions in the same units, which is what gcd tests here -- integer
// arithmetic rather than Hyprland's float division, so a scale like 1.6 cannot
// miss by an ulp.
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)

  if (scaleUnits > 0 && divisor % scaleUnits === 0) return normalizeScale(scaleUnits / 120)

  for (var step = 1; step < 90; step++) {
    if (divisor % (scaleUnits + step) === 0) return normalizeScale((scaleUnits + step) / 120)
    if (scaleUnits - step > 0 && divisor % (scaleUnits - step) === 0)
      return normalizeScale((scaleUnits - step) / 120)
  }

  return ""
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
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var cleaned = cleanScale(requested, width, height)

    // Hyprland rejects the request outright rather than picking something
    // nearby, and falls back to the display's default scale. Offering a preset
    // that lands somewhere the panel cannot name is worse than not offering it.
    if (cleaned === "") continue

    var effective = Number(cleaned)
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
    parseDisplays: parseDisplays
  }
}
