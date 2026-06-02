pragma Singleton
import QtQuick
import "BorderGeometry.js" as Geometry

// Central border-spec factory for shell surfaces and controls. A spec carries
// color, optional gradient, and top/right/bottom/left widths so renderers can
// choose the cheap Rectangle path or the Shape-ring path without duplicating
// theme parsing logic.
QtObject {
  id: root

  function none() {
    return flat("transparent", 0)
  }

  function flat(color, width) {
    return {
      color: color || "transparent",
      widths: Geometry.parseWidthSpec(width, 0),
      gradient: { colors: [], angle: 0, enabled: false },
    }
  }

  function value(section, key) {
    var v = Color.shellValues[section + "." + key]
    return (v === undefined || v === null) ? "" : v
  }

  function valueOr(section, keys) {
    for (var i = 0; i < keys.length; i++) {
      var v = value(section, keys[i])
      if (String(v).length > 0) return v
    }
    return ""
  }

  function alpha(section, key, fallback) {
    var raw = value(section, key)
    if (String(raw).length === 0) return fallback
    var n = Number(raw)
    return isFinite(n) ? Geometry.clampAlpha(n) : fallback
  }

  function cssColor(color, opacity) {
    var a = opacity === undefined || opacity === null ? 1 : Geometry.clampAlpha(opacity)
    if (color && typeof color === "object" && color.r !== undefined) {
      if (typeof Qt !== "undefined" && Qt.rgba) {
        return Qt.rgba(color.r, color.g, color.b, (color.a === undefined ? 1 : color.a) * a)
      }
      return "#"
        + Geometry.padHex(color.r * 255)
        + Geometry.padHex(color.g * 255)
        + Geometry.padHex(color.b * 255)
        + Geometry.padHex((color.a === undefined ? 1 : color.a) * a * 255)
    }

    var s = String(color || "").replace(/^\s+|\s+$/g, "")
    var role = s.toLowerCase()
    if (role === "foreground" || role === "text") return cssColor(Color.foreground, a)
    if (role === "accent") return cssColor(Color.accent, a)
    if (role === "urgent") return cssColor(Color.urgent, a)
    if (role === "background") return cssColor(Color.background, a)
    if (role === "transparent") return "transparent"
    return Geometry.canonicalColor(s, a)
  }

  function resolvedGradient(raw, fallbackColor, opacity) {
    var s = String(raw || "").replace(/^\s+|\s+$/g, "")
    if (s.length === 0) return { colors: [], angle: 0, enabled: false }

    var parts = s.split(/\s+/)
    var colors = []
    var angle = 0
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) angle = Number(parts[i].replace(/deg$/, ""))
      else colors.push(cssColor(parts[i], opacity))
    }
    if (colors.length === 0) colors.push(cssColor(fallbackColor, opacity))
    return { colors: colors, angle: angle, enabled: colors.length > 1 }
  }

  function sameColor(a, b) {
    if (typeof Qt === "undefined" || !Qt.color) return String(a) === String(b)
    var ca = typeof a === "string" ? Qt.color(a) : a
    var cb = typeof b === "string" ? Qt.color(b) : b
    if (!ca || !cb || ca.r === undefined || cb.r === undefined) return String(a) === String(b)
    return Math.round(ca.r * 255) === Math.round(cb.r * 255)
      && Math.round(ca.g * 255) === Math.round(cb.g * 255)
      && Math.round(ca.b * 255) === Math.round(cb.b * 255)
      && Math.round((ca.a === undefined ? 1 : ca.a) * 255) === Math.round((cb.a === undefined ? 1 : cb.a) * 255)
  }

  function localOrSurfaceSpec(section, token, localColor, defaultColor, fallbackWidth, alphaKey) {
    if (!sameColor(localColor, defaultColor)) return flat(localColor, fallbackWidth)
    return surfaceSpec(section, token, localColor, fallbackWidth, alphaKey)
  }

  function surfaceWidths(section, token, fallbackWidth) {
    var base = valueOr(section, token === "border" ? ["border-width"] : [token + "-width", "border-width"])
    var widths = Geometry.parseWidthSpec(base, fallbackWidth)
    return Geometry.withSideOverrides(
      widths,
      valueOr(section, token === "border" ? ["border-width-top"] : [token + "-width-top", "border-width-top"]),
      valueOr(section, token === "border" ? ["border-width-right"] : [token + "-width-right", "border-width-right"]),
      valueOr(section, token === "border" ? ["border-width-bottom"] : [token + "-width-bottom", "border-width-bottom"]),
      valueOr(section, token === "border" ? ["border-width-left"] : [token + "-width-left", "border-width-left"])
    )
  }

  function borderValue(raw, fallbackColor, opacity, legacyGradientRaw) {
    var fallback = cssColor(fallbackColor, opacity)
    var primaryRaw = String(raw || "").replace(/^\s+|\s+$/g, "")
    var primary = resolvedGradient(primaryRaw.length > 0 ? primaryRaw : fallbackColor, fallbackColor, opacity)
    var color = primary.colors.length > 0 ? primary.colors[0] : fallback
    var gradient = primary.enabled ? primary : { colors: [], angle: 0, enabled: false }

    // Backward compatibility for existing configs written during the separate
    // border-gradient experiment. New configs put solid colors and gradients in
    // the same border token.
    if (!gradient.enabled && String(legacyGradientRaw || "").replace(/^\s+|\s+$/g, "").length > 0) {
      var legacy = resolvedGradient(legacyGradientRaw, color, opacity)
      if (legacy.enabled) gradient = legacy
    }

    return { color: color, gradient: gradient }
  }

  function surfaceSpec(section, token, fallbackColor, fallbackWidth, alphaKey) {
    var opacity = alpha(section, alphaKey || token + "-alpha", 1.0)
    var legacyGradientRaw = valueOr(section, token === "border" ? ["border-gradient"] : [token + "-gradient", "border-gradient"])
    var resolved = borderValue(value(section, token), fallbackColor, opacity, legacyGradientRaw)

    return {
      color: resolved.color,
      widths: surfaceWidths(section, token, fallbackWidth),
      gradient: resolved.gradient,
    }
  }

  function controlPrefix(state) {
    if (state === "hover" || state === "hot") return "hover-cursor"
    return state || "normal"
  }

  function controlColor(prefix, foreground, accent, urgent) {
    if (prefix === "focus") return Style.focusStateColor(foreground, accent, urgent)
    if (prefix === "hover-cursor") return Style.hoverStateColor(foreground, accent, urgent)
    if (prefix === "selected") return Style.selectedStateColor(foreground, accent, urgent)
    return Style.normalStateColor(foreground, accent, urgent)
  }

  function controlAlpha(prefix) {
    if (prefix === "focus") return Style.focusBorderAlpha
    if (prefix === "hover-cursor") return Style.hoverBorderAlpha
    if (prefix === "selected") return Style.selectedBorderAlpha
    return Style.normalBorderAlpha
  }

  function controlFallbackWidth(prefix) {
    if (prefix === "focus") return Style.focusBorderWidth
    if (prefix === "hover-cursor") return Style.hoverBorderWidth
    if (prefix === "selected") return Style.selectedBorderWidth
    return Style.normalBorderWidth
  }

  function controlWidths(state) {
    var prefix = controlPrefix(state)
    var fallbackWidth = controlFallbackWidth(prefix)
    var base = Style.styleOverrides[prefix + "-border-width"]
    var widths = Geometry.parseWidthSpec(base, fallbackWidth)
    return Geometry.withSideOverrides(
      widths,
      Style.styleOverrides[prefix + "-border-width-top"],
      Style.styleOverrides[prefix + "-border-width-right"],
      Style.styleOverrides[prefix + "-border-width-bottom"],
      Style.styleOverrides[prefix + "-border-width-left"]
    )
  }

  function controlHasWidth(state) {
    return Geometry.maxWidth(controlWidths(state)) > 0
  }

  function controlSpec(state, foreground, accent, urgent) {
    var prefix = controlPrefix(state)
    var resolved = borderValue(
      Style.styleOverrides[prefix + "-border"],
      controlColor(prefix, foreground, accent, urgent),
      controlAlpha(prefix),
      Style.styleOverrides[prefix + "-border-gradient"]
    )

    return { color: resolved.color, widths: controlWidths(prefix), gradient: resolved.gradient }
  }

  function withWidth(spec, width) {
    if (!spec) return flat("transparent", 0)
    return { color: spec.color, gradient: spec.gradient, widths: Geometry.parseWidthSpec(width, 0) }
  }

  function isNone(spec) { return !spec || Geometry.maxWidth(spec.widths) <= 0 }
  function needsOverlay(spec) { return Geometry.needsOverlay(spec) }
  function canUseNative(spec) { return Geometry.canUseNative(spec) }
  function top(spec) { return spec && spec.widths ? spec.widths.top : 0 }
  function right(spec) { return spec && spec.widths ? spec.widths.right : 0 }
  function bottom(spec) { return spec && spec.widths ? spec.widths.bottom : 0 }
  function left(spec) { return spec && spec.widths ? spec.widths.left : 0 }
  function uniformWidth(spec) { return spec && spec.widths ? spec.widths.top : 0 }
  function color(spec) { return spec ? spec.color : "transparent" }
}
