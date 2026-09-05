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

// ---------- Display-panel arrangement additions ----------
//
// These back the arrangement canvas and per-monitor resolution/scale/
// rotation controls. Identity is `desc:<description>` (falling back to the
// connector name only when a monitor has no EDID description) to match
// omarchy-monitor-arrange's addressing and monitors.lua's existing `desc:`
// selectors — connector names on a DisplayLink dock get reassigned across
// reconnects, so they can't be used as a stable key.

function parseMode(modeString) {
  var s = String(modeString || "")
  var m = s.match(/^([0-9]+)x([0-9]+)@([0-9.]+)(?:Hz)?$/i)
  if (!m) return { width: 0, height: 0, refresh: 0, raw: s }
  return {
    width: parseInt(m[1], 10),
    height: parseInt(m[2], 10),
    refresh: parseFloat(m[3]),
    raw: s
  }
}

function rotateDimensions(width, height, transform) {
  var t = Number(transform) || 0
  if (t === 1 || t === 3) return { width: height, height: width }
  return { width: width, height: height }
}

function monitorIdentity(display) {
  if (!display) return ""
  var desc = String(display.description || "").trim()
  return desc ? "desc:" + desc : String(display.name || "")
}

// Parses omarchy-monitor-state's extended (9th) line: description/serial
// identity plus position/scale/transform/mode/availableModes per display.
function parseExtendedDisplays(raw) {
  var displays = []
  try {
    var parsed = raw ? JSON.parse(String(raw)) : []
    if (Array.isArray(parsed)) displays = parsed
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var normalized = []
  var count = 0
  for (var i = 0; i < displays.length; i++) {
    var d = displays[i]
    if (!d) continue
    var enabled = !!d.enabled
    if (enabled) count++
    normalized.push({
      name: d.name || "",
      description: d.description || "",
      serial: d.serial || "",
      enabled: enabled,
      focused: !!d.focused,
      x: Number(d.x) || 0,
      y: Number(d.y) || 0,
      width: Number(d.width) || 0,
      height: Number(d.height) || 0,
      scale: Number(d.scale) || 1,
      transform: Number(d.transform) || 0,
      currentMode: d.currentMode || "",
      availableModes: Array.isArray(d.availableModes) ? d.availableModes : []
    })
  }

  return {
    displays: normalized,
    enabledDisplayCount: count
  }
}

function arrangementBounds(monitors) {
  var minX = 0
  var minY = 0
  var maxX = 0
  var maxY = 0
  var hasAny = false

  for (var i = 0; i < monitors.length; i++) {
    var d = monitors[i]
    if (!d || !d.enabled) continue
    var dims = rotateDimensions(d.width, d.height, d.transform)
    var left = Number(d.x) || 0
    var top = Number(d.y) || 0
    var right = left + dims.width / Number(d.scale || 1)
    var bottom = top + dims.height / Number(d.scale || 1)

    if (!hasAny) {
      minX = left
      minY = top
      maxX = right
      maxY = bottom
      hasAny = true
    } else {
      if (left < minX) minX = left
      if (top < minY) minY = top
      if (right > maxX) maxX = right
      if (bottom > maxY) maxY = bottom
    }
  }

  return {
    x: minX,
    y: minY,
    width: Math.max(1, maxX - minX),
    height: Math.max(1, maxY - minY)
  }
}

function arrangementCanvasScale(bounds, canvasWidth, canvasHeight, padding) {
  var pad = Number(padding) || 0
  var availW = Math.max(1, canvasWidth - pad * 2)
  var availH = Math.max(1, canvasHeight - pad * 2)
  var scaleX = bounds.width > 0 ? availW / bounds.width : 1
  var scaleY = bounds.height > 0 ? availH / bounds.height : 1
  return Math.min(scaleX, scaleY)
}

function paddedBounds(bounds, fraction) {
  var f = Math.max(0, Number(fraction) || 0)
  var extraX = bounds.width * f
  var extraY = bounds.height * f
  return {
    x: bounds.x - extraX,
    y: bounds.y - extraY,
    width: bounds.width + extraX * 2,
    height: bounds.height + extraY * 2
  }
}

function logicalFromCanvas(canvasDelta, scale) {
  return Number(canvasDelta) / Number(scale || 1)
}

// Lays out enabled+disabled tiles scaled to fit the canvas, centered on both
// axes (rather than pinned to the top-left corner) so the arrangement reads
// as centered regardless of how lopsided the real layout is.
function scaleArrangement(monitors, bounds, canvasWidth, canvasHeight, padding, selectedIdentity) {
  var scale = arrangementCanvasScale(bounds, canvasWidth, canvasHeight, padding)
  var pad = Number(padding) || 0
  var usedW = bounds.width * scale
  var usedH = bounds.height * scale
  var offsetX = pad + Math.max(0, (canvasWidth - pad * 2 - usedW) / 2)
  var offsetY = pad + Math.max(0, (canvasHeight - pad * 2 - usedH) / 2)

  var result = []
  for (var i = 0; i < monitors.length; i++) {
    var d = monitors[i]
    if (!d) continue
    var dims = rotateDimensions(d.width, d.height, d.transform)
    var logicalW = dims.width / Number(d.scale || 1)
    var logicalH = dims.height / Number(d.scale || 1)
    var identity = monitorIdentity(d)
    result.push({
      identity: identity,
      name: d.name,
      x: offsetX + ((Number(d.x) || 0) - bounds.x) * scale,
      y: offsetY + ((Number(d.y) || 0) - bounds.y) * scale,
      width: logicalW * scale,
      height: logicalH * scale,
      enabled: !!d.enabled,
      focused: !!d.focused,
      selected: identity === selectedIdentity
    })
  }
  return result
}

function compactModes(modes, current, limit) {
  var result = []
  var seen = {}
  var max = Math.max(1, Number(limit) || 6)
  function add(mode) {
    var value = String(mode || "")
    if (!value || seen[value] || result.length >= max) return
    seen[value] = true
    result.push(value)
  }
  add(current)
  for (var i = 0; i < (modes || []).length && result.length < max; i++) add(modes[i])
  return result
}

function modeOptions(modes, current, limit) {
  return compactModes(modes, current, limit).map(function(value) {
    var parsed = parseMode(value)
    var label = parsed.width > 0
      ? (parsed.width + "×" + parsed.height + " " + Math.round(parsed.refresh) + "Hz")
      : value
    return { label: label, value: value }
  })
}

// Diffs pending per-identity edits against live state, dropping any pending
// entry that no longer differs (e.g. the user dialed a value back to what it
// already was) so `dirty`/the Apply footer only reflect real changes.
function diffPending(displaysByIdentity, pending) {
  var out = {}
  var keys = Object.keys(pending || {})
  for (var i = 0; i < keys.length; i++) {
    var identity = keys[i]
    var cur = displaysByIdentity[identity]
    var pend = pending[identity]
    if (!cur || !pend) continue

    var changes = {}
    if (pend.enabled !== undefined && pend.enabled !== cur.enabled) changes.enabled = pend.enabled
    if (pend.mode && pend.mode !== cur.currentMode) changes.mode = pend.mode
    if (pend.scale !== undefined && normalizeScale(pend.scale) !== normalizeScale(cur.scale)) changes.scale = pend.scale
    if (pend.transform !== undefined && Number(pend.transform) !== Number(cur.transform)) changes.transform = Number(pend.transform)
    if (pend.x !== undefined && Number(pend.x) !== Number(cur.x)) changes.x = Number(pend.x)
    if (pend.y !== undefined && Number(pend.y) !== Number(cur.y)) changes.y = Number(pend.y)

    if (Object.keys(changes).length > 0) out[identity] = changes
  }
  return out
}

function isDirty(pendingDiff) {
  return Object.keys(pendingDiff || {}).length > 0
}

// Builds the JSON layout array omarchy-monitor-arrange expects (apply and
// persist share this shape), merging live display state with pending edits.
function buildArrangeLayout(displays, pendingDiff) {
  var diff = pendingDiff || {}
  var layout = []
  for (var i = 0; i < displays.length; i++) {
    var d = displays[i]
    if (!d) continue
    var identity = monitorIdentity(d)
    var changes = diff[identity] || {}
    layout.push({
      identity: identity,
      mode: changes.mode || d.currentMode || "preferred",
      x: changes.x !== undefined ? changes.x : d.x,
      y: changes.y !== undefined ? changes.y : d.y,
      scale: Number(changes.scale !== undefined ? changes.scale : d.scale) || 1,
      transform: Number(changes.transform !== undefined ? changes.transform : d.transform) || 0,
      enabled: changes.enabled !== undefined ? changes.enabled : d.enabled
    })
  }
  return layout
}

// Parses {"success":bool,"message":string} from omarchy-monitor-arrange.
function parseArrangeResult(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    return {
      success: !!parsed.success,
      message: String(parsed.message || "")
    }
  } catch (e) {
    return { success: false, message: "invalid backend response" }
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
    parseMode: parseMode,
    rotateDimensions: rotateDimensions,
    monitorIdentity: monitorIdentity,
    parseExtendedDisplays: parseExtendedDisplays,
    arrangementBounds: arrangementBounds,
    arrangementCanvasScale: arrangementCanvasScale,
    paddedBounds: paddedBounds,
    logicalFromCanvas: logicalFromCanvas,
    scaleArrangement: scaleArrangement,
    compactModes: compactModes,
    modeOptions: modeOptions,
    diffPending: diffPending,
    isDirty: isDirty,
    buildArrangeLayout: buildArrangeLayout,
    parseArrangeResult: parseArrangeResult
  }
}
