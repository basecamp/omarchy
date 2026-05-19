pragma Singleton
import QtQuick

// Shared utility helpers used across plugins. Pure functions only — no
// state. Anything stateful belongs on Color, Style, or a service.
QtObject {
  id: root

  // Compose a base color with an opacity. Accepts a color object or a hex
  // string; null/undefined yields transparent black at the requested alpha.
  function alpha(c, opacity) {
    if (!c) return Qt.rgba(0, 0, 0, opacity)
    if (typeof c === "string") c = Qt.color(c)
    return Qt.rgba(c.r, c.g, c.b, opacity)
  }

  // file:// URL with each path segment percent-encoded so spaces and
  // special chars in user paths don't break Image.source.
  function fileUrl(path) {
    if (!path) return ""
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  // Single-quote a string for bash. The replace handles embedded single
  // quotes by closing, escaping, and re-opening the literal.
  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  // Best-effort base64 decode. Returns "" on parse failure rather than
  // surfacing garbage downstream.
  function decodeBase64(value) {
    var s = String(value || "")
    if (!s) return ""
    try { return Qt.atob(s) } catch (e) { return "" }
  }

  function cloneJson(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value))
  }

  // Layout normalization shared by the bar host and the bar settings panel
  // so the two never drift. Entries are deep-cloned to decouple from the
  // input config; consumers can mutate without leaking back to shell.json.
  function normalizeLayoutEntry(entry) {
    if (typeof entry === "string") return { id: entry }
    if (isPlainObject(entry) && entry.id) return cloneJson(entry)
    return null
  }

  function normalizeLayoutSection(list) {
    if (!Array.isArray(list)) return []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var e = normalizeLayoutEntry(list[i])
      if (e) out.push(e)
    }
    return out
  }

  function normalizeLayout(layout) {
    var src = isPlainObject(layout) ? layout : {}
    return {
      left:   normalizeLayoutSection(src.left),
      center: normalizeLayoutSection(src.center),
      right:  normalizeLayoutSection(src.right)
    }
  }
}
