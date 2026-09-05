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
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

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

// An output's scale and position can only be read dependably while it is on,
// and bringing one back with "auto" for both re-places the display and drops a
// scaled one to 1. Carry the last values seen while an output was on, so
// switching it back on restores the layout it had.
function rememberLayouts(previous, displays) {
  var layouts = {}
  for (var name in previous) layouts[name] = previous[name]
  if (!Array.isArray(displays)) return layouts

  for (var i = 0; i < displays.length; i++) {
    var display = displays[i]
    if (!display || !display.name || !display.enabled) continue

    var scale = Number(display.scale)
    var x = Number(display.x)
    var y = Number(display.y)
    if (!isFinite(scale) || scale <= 0 || !isFinite(x) || !isFinite(y)) continue

    layouts[display.name] = { scale: scale, position: x + "x" + y }
  }

  return layouts
}

// Omarchy configures Hyprland through the Lua parser, which rejects
// `hyprctl keyword` outright ("keyword can't work with non-legacy parsers. Use
// eval.") while still exiting 0 — so a keyword-based toggle fails silently.
// `disabled = false` has to be spelled out as well: restating a mode alone
// leaves an already-disabled output off.
function monitorRule(name, disable, layout) {
  if (disable) return 'hl.monitor({ output = "' + name + '", disabled = true })'

  var position = layout && layout.position ? layout.position : "auto"
  var scale = layout && layout.scale ? String(layout.scale) : '"auto"'

  return 'hl.monitor({ output = "' + name + '", disabled = false, mode = "preferred"' +
    ', position = "' + position + '"' +
    ', scale = ' + scale + ' })'
}

// The rates a display offers at the resolution it is running, highest first.
// Hyprland lists modes as "2560x1440@240.00Hz", and a mode list can hold the
// same rate twice at different timings.
function availableRates(display) {
  if (!display) return []

  var prefix = display.width + "x" + display.height + "@"
  var modes = display.availableModes || []
  var rates = []

  for (var i = 0; i < modes.length; i++) {
    var mode = String(modes[i])
    if (mode.indexOf(prefix) !== 0) continue

    var rate = Math.round(parseFloat(mode.slice(prefix.length)))
    if (!isFinite(rate) || rate <= 0) continue
    if (rates.indexOf(rate) < 0) rates.push(rate)
  }

  rates.sort(function (a, b) { return b - a })
  return rates
}

// Hyprland reports 143.979 where the mode string says 144.
function activeRate(display) {
  if (!display) return 0

  var rate = Math.round(Number(display.refreshRate))
  return isFinite(rate) && rate > 0 ? rate : 0
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
    rememberLayouts: rememberLayouts,
    monitorRule: monitorRule,
    availableRates: availableRates,
    activeRate: activeRate
  }
}
