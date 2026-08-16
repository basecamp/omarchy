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

function layoutSize(width, height, scale) {
  var s = Number(scale)
  if (!isFinite(s) || s <= 0) s = 1
  return {
    w: Math.floor(Number(width) / s),
    h: Math.floor(Number(height) / s)
  }
}

function snapPosition(moved, others) {
  return snapWindows(moved, others)
}

function snapWindows(moved, others, prefer) {
  function clamp(v, a, b) {
    if (a > b) return Math.round((a + b) / 2)
    if (v < a) return a
    if (v > b) return b
    return v
  }

  function sideFor(o) {
    var cx = moved.x + moved.w / 2
    var cy = moved.y + moved.h / 2
    var left = o.x
    var right = o.x + o.w
    var top = o.y
    var bottom = o.y + o.h
    var outLeft = Math.max(0, left - cx)
    var outRight = Math.max(0, cx - right)
    var outTop = Math.max(0, top - cy)
    var outBottom = Math.max(0, cy - bottom)
    var outX = Math.max(outLeft, outRight)
    var outY = Math.max(outTop, outBottom)
    if (prefer === "vertical") return outTop > 0 || (outY === 0 && (cy - top) < (bottom - cy)) ? "top" : "bottom"
    if (prefer === "horizontal") return outLeft > 0 || (outX === 0 && (cx - left) < (right - cx)) ? "left" : "right"
    if (outY > outX) return outTop > 0 ? "top" : "bottom"
    if (outX > outY) return outLeft > 0 ? "left" : "right"
    var distLeft = cx - left
    var distRight = right - cx
    var distTop = cy - top
    var distBottom = bottom - cy
    var nearest = Math.min(distLeft, distRight, distTop, distBottom)
    if (nearest === distBottom) return "bottom"
    if (nearest === distTop) return "top"
    if (nearest === distLeft) return "left"
    return "right"
  }

  var best = null
  var bestDist = Infinity
  var overlap = 48
  for (var i = 0; i < others.length; i++) {
    var o = others[i]
    var minY = o.y + overlap - moved.h
    var maxY = o.y + o.h - overlap
    var minX = o.x + overlap - moved.w
    var maxX = o.x + o.w - overlap
    var side = sideFor(o)
    var c = side === "right" ? { side: "right", x: o.x + o.w, y: clamp(moved.y, minY, maxY) }
      : side === "left" ? { side: "left", x: o.x - moved.w, y: clamp(moved.y, minY, maxY) }
      : side === "bottom" ? { side: "bottom", x: clamp(moved.x, minX, maxX), y: o.y + o.h }
      : { side: "top", x: clamp(moved.x, minX, maxX), y: o.y - moved.h }
    var dx = c.x - moved.x
    var dy = c.y - moved.y
    var dist = dx * dx + dy * dy
    if (dist < bestDist) {
      bestDist = dist
      best = c
    }
  }
  return best
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
    layoutSize: layoutSize,
    snapPosition: snapPosition,
    snapWindows: snapWindows
  }
}
