.pragma library

function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function clampAlpha(value) {
  return clamp(value, 0, 1)
}

function padHex(value) {
  var n = clamp(Math.round(Number(value)), 0, 255)
  var h = n.toString(16)
  return h.length < 2 ? "0" + h : h
}

function qmlHexColor(rgb, alphaByte) {
  var rgbPart = String(rgb || "").replace(/^#/, "")
  var a = clamp(Math.round(Number(alphaByte)), 0, 255)

  if (typeof Qt !== "undefined" && Qt.rgba && rgbPart.length >= 6) {
    return Qt.rgba(
      parseInt(rgbPart.substring(0, 2), 16) / 255,
      parseInt(rgbPart.substring(2, 4), 16) / 255,
      parseInt(rgbPart.substring(4, 6), 16) / 255,
      a / 255
    )
  }

  var aHex = padHex(a)
  return aHex.toLowerCase() === "ff" ? "#" + rgbPart : "#" + rgbPart + aHex
}

function canonicalColor(value, alpha) {
  var a = alpha === undefined || alpha === null ? 1 : clampAlpha(alpha)
  var s = String(value || "").replace(/^\s+|\s+$/g, "")
  var m

  m = s.match(/^#([0-9A-Fa-f]{3})$/)
  if (m) {
    var sh = m[1]
    return qmlHexColor(
      sh.charAt(0) + sh.charAt(0)
        + sh.charAt(1) + sh.charAt(1)
        + sh.charAt(2) + sh.charAt(2),
      a * 255
    )
  }

  m = s.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/)
  if (m) {
    var colorAlpha = m[2] ? parseInt(m[2], 16) / 255 : 1
    return qmlHexColor(m[1], colorAlpha * a * 255)
  }

  m = s.match(/^[Rr][Gg][Bb]\(([0-9A-Fa-f]{6})\)$/)
  if (m) return qmlHexColor(m[1], a * 255)

  m = s.match(/^[Rr][Gg][Bb][Aa]\(([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})\)$/)
  if (m) return qmlHexColor(m[1], (parseInt(m[2], 16) / 255) * a * 255)

  m = s.match(/^[Rr][Gg][Bb]\(([0-9]+),([0-9]+),([0-9]+)\)$/)
  if (m) return qmlHexColor(padHex(m[1]) + padHex(m[2]) + padHex(m[3]), a * 255)

  m = s.match(/^[Rr][Gg][Bb][Aa]\(([0-9]+),([0-9]+),([0-9]+),([0-9.]+)\)$/)
  if (m) return qmlHexColor(padHex(m[1]) + padHex(m[2]) + padHex(m[3]), clampAlpha(m[4]) * a * 255)

  m = s.match(/^0x([0-9A-Fa-f]{2})([0-9A-Fa-f]{6})$/)
  if (m) return qmlHexColor(m[2], (parseInt(m[1], 16) / 255) * a * 255)

  return s
}

function parseWidthSpec(value, fallback) {
  var fb = Number(fallback)
  if (!isFinite(fb) || fb < 0) fb = 0

  if (value === undefined || value === null || value === "") {
    return { top: fb, right: fb, bottom: fb, left: fb }
  }

  var parts = String(value).match(/-?\d+(?:\.\d+)?/g) || []
  var nums = []
  for (var i = 0; i < parts.length && i < 4; i++) {
    var n = Number(parts[i])
    nums.push(isFinite(n) && n > 0 ? n : 0)
  }

  if (nums.length === 0) nums = [fb]
  if (nums.length === 1) return { top: nums[0], right: nums[0], bottom: nums[0], left: nums[0] }
  if (nums.length === 2) return { top: nums[0], right: nums[1], bottom: nums[0], left: nums[1] }
  if (nums.length === 3) return { top: nums[0], right: nums[1], bottom: nums[2], left: nums[1] }
  return { top: nums[0], right: nums[1], bottom: nums[2], left: nums[3] }
}

function withSideOverrides(widths, top, right, bottom, left) {
  var out = {
    top: Number(widths && widths.top) || 0,
    right: Number(widths && widths.right) || 0,
    bottom: Number(widths && widths.bottom) || 0,
    left: Number(widths && widths.left) || 0,
  }
  if (top !== undefined && top !== null && top !== "") out.top = Math.max(0, Number(top) || 0)
  if (right !== undefined && right !== null && right !== "") out.right = Math.max(0, Number(right) || 0)
  if (bottom !== undefined && bottom !== null && bottom !== "") out.bottom = Math.max(0, Number(bottom) || 0)
  if (left !== undefined && left !== null && left !== "") out.left = Math.max(0, Number(left) || 0)
  return out
}

function parseGradientSpec(value, fallbackColor, alpha) {
  var s = String(value || "").replace(/^\s+|\s+$/g, "")
  var colors = []
  var angle = 0
  var parts = s.length > 0 ? s.split(/\s+/) : []

  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    var angleMatch = part.match(/^(-?\d+(?:\.\d+)?)deg$/)
    if (angleMatch) angle = Number(angleMatch[1])
    else colors.push(canonicalColor(part, alpha))
  }

  if (colors.length === 0 && fallbackColor !== undefined && fallbackColor !== null)
    colors.push(canonicalColor(fallbackColor, alpha))

  return {
    colors: colors,
    angle: isFinite(angle) ? angle : 0,
    enabled: colors.length > 1,
  }
}

function isUniform(widths) {
  if (!widths) return true
  return widths.top === widths.right && widths.top === widths.bottom && widths.top === widths.left
}

function maxWidth(widths) {
  if (!widths) return 0
  return Math.max(widths.top || 0, widths.right || 0, widths.bottom || 0, widths.left || 0)
}

function needsOverlay(spec) {
  if (!spec) return false
  if (maxWidth(spec.widths) <= 0) return false
  return !!(spec.gradient && spec.gradient.enabled) || !isUniform(spec.widths)
}

function canUseNative(spec) {
  return !!spec && maxWidth(spec.widths) > 0 && !needsOverlay(spec)
}

function normalizeRadii(w, h, r) {
  var tl = { rx: Math.max(0, Number(r.tlrx) || 0), ry: Math.max(0, Number(r.tlry) || 0) }
  var tr = { rx: Math.max(0, Number(r.trrx) || 0), ry: Math.max(0, Number(r.trry) || 0) }
  var br = { rx: Math.max(0, Number(r.brrx) || 0), ry: Math.max(0, Number(r.brry) || 0) }
  var bl = { rx: Math.max(0, Number(r.blrx) || 0), ry: Math.max(0, Number(r.blry) || 0) }
  var scale = 1

  if (tl.rx + tr.rx > w && tl.rx + tr.rx > 0) scale = Math.min(scale, w / (tl.rx + tr.rx))
  if (bl.rx + br.rx > w && bl.rx + br.rx > 0) scale = Math.min(scale, w / (bl.rx + br.rx))
  if (tl.ry + bl.ry > h && tl.ry + bl.ry > 0) scale = Math.min(scale, h / (tl.ry + bl.ry))
  if (tr.ry + br.ry > h && tr.ry + br.ry > 0) scale = Math.min(scale, h / (tr.ry + br.ry))

  if (scale < 1) {
    tl.rx *= scale; tr.rx *= scale; br.rx *= scale; bl.rx *= scale
    tl.ry *= scale; tr.ry *= scale; br.ry *= scale; bl.ry *= scale
  }

  return { tl: tl, tr: tr, br: br, bl: bl }
}

function roundedRectPath(x, y, w, h, radii) {
  if (w <= 0 || h <= 0) return ""
  var r = normalizeRadii(w, h, radii)
  var right = x + w
  var bottom = y + h
  var p = []

  p.push("M", x + r.tl.rx, y)
  p.push("H", right - r.tr.rx)
  if (r.tr.rx > 0 || r.tr.ry > 0) p.push("A", r.tr.rx, r.tr.ry, 0, 0, 1, right, y + r.tr.ry)
  p.push("V", bottom - r.br.ry)
  if (r.br.rx > 0 || r.br.ry > 0) p.push("A", r.br.rx, r.br.ry, 0, 0, 1, right - r.br.rx, bottom)
  p.push("H", x + r.bl.rx)
  if (r.bl.rx > 0 || r.bl.ry > 0) p.push("A", r.bl.rx, r.bl.ry, 0, 0, 1, x, bottom - r.bl.ry)
  p.push("V", y + r.tl.ry)
  if (r.tl.rx > 0 || r.tl.ry > 0) p.push("A", r.tl.rx, r.tl.ry, 0, 0, 1, x + r.tl.rx, y)
  p.push("Z")

  return p.join(" ")
}

function ringPath(w, h, radius, widths) {
  w = Math.max(0, Number(w) || 0)
  h = Math.max(0, Number(h) || 0)
  radius = Math.max(0, Number(radius) || 0)
  widths = widths || { top: 0, right: 0, bottom: 0, left: 0 }

  var outer = roundedRectPath(0, 0, w, h, {
    tlrx: radius, tlry: radius,
    trrx: radius, trry: radius,
    brrx: radius, brry: radius,
    blrx: radius, blry: radius,
  })

  // Shape's OddEven fill can collapse to the outer fill when the inner
  // cutout touches the outer path on one or more zero-width sides. Keep the
  // cutout strictly inside the outer path with a subpixel inset so one-sided
  // borders (for example selected-border-width = "0 0 0 4") render as a
  // strip instead of painting the whole row.
  var epsilon = 0.001
  var left = Math.max(0, widths.left || 0)
  var top = Math.max(0, widths.top || 0)
  var right = Math.max(0, widths.right || 0)
  var bottom = Math.max(0, widths.bottom || 0)
  var ix = Math.max(left, epsilon)
  var iy = Math.max(top, epsilon)
  var ir = Math.max(right, epsilon)
  var ib = Math.max(bottom, epsilon)
  var iw = w - ix - ir
  var ih = h - iy - ib
  if (iw <= 0 || ih <= 0) return outer

  var inner = roundedRectPath(ix, iy, iw, ih, {
    tlrx: Math.max(0, radius - left),
    tlry: Math.max(0, radius - top),
    trrx: Math.max(0, radius - right),
    trry: Math.max(0, radius - top),
    brrx: Math.max(0, radius - right),
    brry: Math.max(0, radius - bottom),
    blrx: Math.max(0, radius - left),
    blry: Math.max(0, radius - bottom),
  })

  return outer + " " + inner
}

function gradientEndpoints(w, h, angle) {
  w = Math.max(1, Number(w) || 1)
  h = Math.max(1, Number(h) || 1)
  var rad = (Number(angle) || 0) * Math.PI / 180
  var dx = Math.cos(rad)
  var dy = Math.sin(rad)
  var len = (Math.abs(w * dx) + Math.abs(h * dy)) / 2
  var cx = w / 2
  var cy = h / 2
  return {
    x1: cx - dx * len,
    y1: cy - dy * len,
    x2: cx + dx * len,
    y2: cy + dy * len,
  }
}

function stopColor(colors, index) {
  if (!colors || colors.length === 0) return "transparent"
  if (index < colors.length) return colors[index]
  return colors[colors.length - 1]
}

function stopPosition(colors, index) {
  var count = colors ? colors.length : 0
  if (count <= 1) return index === 0 ? 0 : 1
  if (index >= count) return 1
  return index / (count - 1)
}
