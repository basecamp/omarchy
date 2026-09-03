// Geometry for the display arrangement canvas.
//
// Everything here works in Hyprland's logical pixels — mode size divided by
// scale — because that is the space positions are expressed in and the space
// the pointer actually crosses between displays. Drawing raw mode sizes would
// show two rectangles whose relative sizes have nothing to do with how the
// desktop behaves.

// The built-in panel, by the connector names Hyprland gives it.
function isInternalName(name) {
  return /^(eDP|LVDS|DSI)-/.test(String(name || ""))
}

// Whether the live displays include a built-in panel, or an external one. Fed
// the active listing rather than `monitors all`, so a display the user switched
// off does not count as one that mirroring can act on.
function hasActiveDisplay(displays, internal) {
  if (!Array.isArray(displays)) return false

  for (var i = 0; i < displays.length; i++) {
    if (isInternalName(displays[i] && displays[i].name) === internal) return true
  }
  return false
}

// Transforms 1, 3, 5 and 7 are the 90 and 270 degree rotations, which swap the
// display's width and height.
function isRotated(transform) {
  var t = Number(transform)
  return t === 1 || t === 3 || t === 5 || t === 7
}

// A display as it occupies the layout: logical size at its logical position.
function logicalRect(display) {
  if (!display) return null

  var scale = Number(display.scale)
  if (!isFinite(scale) || scale <= 0) scale = 1

  var width = Number(display.width) / scale
  var height = Number(display.height) / scale
  if (!isFinite(width) || !isFinite(height)) return null

  if (isRotated(display.transform)) {
    var swap = width
    width = height
    height = swap
  }

  return {
    name: String(display.name || ""),
    x: Math.round(Number(display.x) || 0),
    y: Math.round(Number(display.y) || 0),
    width: Math.round(width),
    height: Math.round(height)
  }
}

function logicalRects(displays) {
  var rects = []
  if (!Array.isArray(displays)) return rects

  for (var i = 0; i < displays.length; i++) {
    var rect = logicalRect(displays[i])
    if (rect && rect.width > 0 && rect.height > 0) rects.push(rect)
  }
  return rects
}

function bounds(rects) {
  if (!Array.isArray(rects) || rects.length === 0) return { x: 0, y: 0, width: 0, height: 0 }

  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (var i = 0; i < rects.length; i++) {
    var r = rects[i]
    if (r.x < minX) minX = r.x
    if (r.y < minY) minY = r.y
    if (r.x + r.width > maxX) maxX = r.x + r.width
    if (r.y + r.height > maxY) maxY = r.y + r.height
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
}

// Scale factor that fits the whole layout inside the canvas with room to
// spare, so a display dragged past the edge still has somewhere to go.
function fitScale(rects, canvasWidth, canvasHeight, padding) {
  var box = bounds(rects)
  var pad = Number(padding) || 0
  var availableWidth = Number(canvasWidth) - pad * 2
  var availableHeight = Number(canvasHeight) - pad * 2

  if (box.width <= 0 || box.height <= 0 || availableWidth <= 0 || availableHeight <= 0) return 1

  return Math.min(availableWidth / box.width, availableHeight / box.height)
}

function overlaps(a, b) {
  return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
}

function anyOverlap(rects) {
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      if (overlaps(rects[i], rects[j])) return true
    }
  }
  return false
}

// Gaps between displays are dead zones the pointer cannot cross, so a layout
// wants every display touching at least one other. A single display is
// trivially connected.
function isContiguous(rects) {
  if (!Array.isArray(rects) || rects.length < 2) return true

  var seen = {}
  var queue = [rects[0]]
  seen[rects[0].name] = true

  while (queue.length > 0) {
    var current = queue.shift()
    for (var i = 0; i < rects.length; i++) {
      var other = rects[i]
      if (seen[other.name]) continue
      if (touches(current, other)) {
        seen[other.name] = true
        queue.push(other)
      }
    }
  }

  for (var j = 0; j < rects.length; j++) {
    if (!seen[rects[j].name]) return false
  }
  return true
}

// Sharing an edge, not merely a corner: two displays meeting at a point leave
// no width for the pointer to cross through.
function touches(a, b) {
  var horizontallyAdjacent = (a.x + a.width === b.x || b.x + b.width === a.x) &&
    a.y < b.y + b.height && a.y + a.height > b.y
  var verticallyAdjacent = (a.y + a.height === b.y || b.y + b.height === a.y) &&
    a.x < b.x + b.width && a.x + a.width > b.x

  return horizontallyAdjacent || verticallyAdjacent
}

// Pull a dragged display onto its neighbours' edges. Snapping is what makes a
// layout usable rather than a nicety: a few logical pixels of gap is a strip
// the pointer cannot cross, and a few pixels of overlap puts part of one
// display underneath another.
function snap(moving, others, threshold) {
  var limit = Number(threshold)
  if (!isFinite(limit) || limit <= 0) limit = 0

  var x = moving.x
  var y = moving.y
  var bestX = limit + 1
  var bestY = limit + 1

  for (var i = 0; i < others.length; i++) {
    var other = others[i]
    if (other.name === moving.name) continue

    // Edge-to-edge in x: right against left, left against right, plus the two
    // flush alignments.
    var xCandidates = [
      other.x + other.width,
      other.x - moving.width,
      other.x,
      other.x + other.width - moving.width
    ]
    for (var xi = 0; xi < xCandidates.length; xi++) {
      var dx = Math.abs(xCandidates[xi] - moving.x)
      if (dx <= limit && dx < bestX) {
        bestX = dx
        x = xCandidates[xi]
      }
    }

    var yCandidates = [
      other.y + other.height,
      other.y - moving.height,
      other.y,
      other.y + other.height - moving.height
    ]
    for (var yi = 0; yi < yCandidates.length; yi++) {
      var dy = Math.abs(yCandidates[yi] - moving.y)
      if (dy <= limit && dy < bestY) {
        bestY = dy
        y = yCandidates[yi]
      }
    }
  }

  return { name: moving.name, x: Math.round(x), y: Math.round(y), width: moving.width, height: moving.height }
}

// Push a display clear of anything it lands on, by the shortest move that
// frees it. Overlapping displays put part of one desktop underneath another,
// and a layout that cannot express the mistake is better than one that reports
// it: the user drops a display roughly where they want it and it settles
// somewhere valid rather than refusing to apply.
function pushOut(moving, others) {
  var current = { name: moving.name, x: moving.x, y: moving.y, width: moving.width, height: moving.height }

  // Each resolved collision can create another, so settle repeatedly. The
  // bound is a guard against a pathological layout, not an expected path.
  for (var pass = 0; pass < 8; pass++) {
    var hit = null
    for (var i = 0; i < others.length; i++) {
      if (others[i].name !== current.name && overlaps(current, others[i])) {
        hit = others[i]
        break
      }
    }
    if (!hit) return current

    var candidates = [
      { x: hit.x - current.width, y: current.y },
      { x: hit.x + hit.width, y: current.y },
      { x: current.x, y: hit.y - current.height },
      { x: current.x, y: hit.y + hit.height }
    ]

    var best = null
    var bestDistance = Infinity
    for (var c = 0; c < candidates.length; c++) {
      var dx = candidates[c].x - current.x
      var dy = candidates[c].y - current.y
      var distance = Math.abs(dx) + Math.abs(dy)
      if (distance < bestDistance) {
        bestDistance = distance
        best = candidates[c]
      }
    }

    current = { name: current.name, x: best.x, y: best.y, width: current.width, height: current.height }
  }

  return current
}

// Rotating a display swaps the edges it presents to the layout, so the canvas
// has to re-measure it rather than just relabel it.
function rotated(rect, fromTransform, toTransform) {
  var swap = isRotated(fromTransform) !== isRotated(toTransform)
  return {
    name: rect.name,
    x: rect.x,
    y: rect.y,
    width: swap ? rect.height : rect.width,
    height: swap ? rect.width : rect.height
  }
}

// The four rotations Omarchy offers, as Hyprland transform values.
var TRANSFORMS = [0, 1, 2, 3]

function nextTransform(transform) {
  var index = TRANSFORMS.indexOf(Number(transform) || 0)
  if (index < 0) index = 0
  return TRANSFORMS[(index + 1) % TRANSFORMS.length]
}

function transformLabel(transform) {
  switch (Number(transform) || 0) {
    case 1: return "90°"
    case 2: return "180°"
    case 3: return "270°"
    default: return "0°"
  }
}

function clamp(value, low, high) {
  if (low > high) return low
  return Math.min(Math.max(value, low), high)
}

function touchesAny(rect, others) {
  for (var i = 0; i < others.length; i++) {
    if (others[i].name !== rect.name && touches(rect, others[i])) return true
  }
  return false
}

// Pull a display that is floating free onto its nearest neighbour. A gap
// between displays is not a layout choice: it is a strip of desktop the pointer
// cannot cross, so nothing useful lives there. Displays always end up touching.
//
// The perpendicular axis is clamped so they share a real edge rather than
// meeting at a corner, which would leave nothing to cross through either.
function attach(moving, others) {
  if (!Array.isArray(others) || others.length === 0) return moving
  if (touchesAny(moving, others)) return moving

  var best = null
  var bestDistance = Infinity

  for (var i = 0; i < others.length; i++) {
    var other = others[i]
    if (other.name === moving.name) continue

    // Share at least half of the smaller display's edge, so the crossing is
    // wide enough to find with a pointer.
    var shareY = Math.min(moving.height, other.height) / 2
    var shareX = Math.min(moving.width, other.width) / 2
    var alignedY = clamp(moving.y, other.y - moving.height + shareY, other.y + other.height - shareY)
    var alignedX = clamp(moving.x, other.x - moving.width + shareX, other.x + other.width - shareX)

    var candidates = [
      { x: other.x + other.width, y: alignedY },
      { x: other.x - moving.width, y: alignedY },
      { x: alignedX, y: other.y + other.height },
      { x: alignedX, y: other.y - moving.height }
    ]

    for (var c = 0; c < candidates.length; c++) {
      var distance = Math.abs(candidates[c].x - moving.x) + Math.abs(candidates[c].y - moving.y)
      if (distance < bestDistance) {
        bestDistance = distance
        best = candidates[c]
      }
    }
  }

  if (!best) return moving
  return {
    name: moving.name,
    x: Math.round(best.x),
    y: Math.round(best.y),
    width: moving.width,
    height: moving.height
  }
}

// Shift the whole layout so its top-left sits at the origin. Hyprland accepts
// negative positions, but keeping them non-negative makes the numbers readable
// and keeps repeated edits from drifting away from zero.
function normalized(rects) {
  var box = bounds(rects)
  var out = []

  for (var i = 0; i < rects.length; i++) {
    out.push({
      name: rects[i].name,
      x: rects[i].x - box.x,
      y: rects[i].y - box.y,
      width: rects[i].width,
      height: rects[i].height
    })
  }
  return out
}

function positionsOf(rects) {
  var out = {}
  for (var i = 0; i < rects.length; i++) out[rects[i].name] = rects[i].x + "x" + rects[i].y
  return out
}

// Only displays that actually moved need writing, so an arrangement that
// nudges one display does not rewrite every rule.
function changedPositions(before, after) {
  var from = positionsOf(before)
  var to = positionsOf(after)
  var changed = {}

  for (var name in to) {
    if (from[name] !== to[name]) changed[name] = to[name]
  }
  return changed
}

// The display glyph the panel and notifications use. Written literally: it sits
// outside the basic plane, and a "\u" escape takes exactly four hex digits, so
// "\uf0379" is U+F037 followed by a stray "9" rather than this one character.
var displayGlyph = "\udb80\udf79"

if (typeof module !== "undefined") {
  module.exports = {
    displayGlyph: displayGlyph,
    isInternalName: isInternalName,
    hasActiveDisplay: hasActiveDisplay,
    isRotated: isRotated,
    logicalRect: logicalRect,
    logicalRects: logicalRects,
    bounds: bounds,
    fitScale: fitScale,
    overlaps: overlaps,
    anyOverlap: anyOverlap,
    touches: touches,
    isContiguous: isContiguous,
    snap: snap,
    pushOut: pushOut,
    attach: attach,
    rotated: rotated,
    nextTransform: nextTransform,
    transformLabel: transformLabel,
    touchesAny: touchesAny,
    normalized: normalized,
    positionsOf: positionsOf,
    changedPositions: changedPositions
  }
}
