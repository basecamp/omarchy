pragma Singleton
import Quickshell
import QtQuick

// Shared utility helpers used across plugins. Pure functions only — no
// state. Anything stateful belongs on Color, Style, or a service.
QtObject {
  id: root

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  function clamp(value, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return min
    return Math.max(min, Math.min(max, n))
  }

  function clampAlpha(value) {
    return clamp(value, 0, 1)
  }

  // Compose a base color with an opacity. Accepts a color object or a hex
  // string; null/undefined yields transparent black at the requested alpha.
  function alpha(c, opacity) {
    var a = clampAlpha(opacity)
    if (!c) return Qt.rgba(0, 0, 0, a)
    if (typeof c === "string") c = Qt.color(c)
    return Qt.rgba(c.r, c.g, c.b, a)
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

  function hyprExecCommand(command) {
    return [omarchyPath + "/bin/omarchy-hyprland-launch", command]
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function canonicalWidgetId(id) {
    return String(id || "")
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

  // Parse the last line of a custom-module / indicator process output as
  // waybar-style JSON ({text, class, tooltip, ...}). Falls back to {text: raw}
  // when the output isn't JSON, and {} for empty output.
  function parseModuleJson(raw) {
    var text = String(raw || "").trim()
    if (!text) return {}
    var lines = text.split("\n")
    try {
      return JSON.parse(lines[lines.length - 1])
    } catch (e) {
      return { text: text }
    }
  }

  // Standard Qt text-editing keys shared by every searchable panel's filter:
  //   Backspace       delete previous character
  //   Ctrl+Backspace  delete previous word (Qt DeleteStartOfWord)
  //   Ctrl+U          clear the whole field
  // Panels decide how to apply the result (setFilter/updateFilter) and keep
  // their own empty-field fallbacks (e.g. menu back-navigation).
  function isFilterEditKey(event) {
    return event.key === Qt.Key_Backspace
        || (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier))
  }

  // New filter text after applying an edit key. Assumes isFilterEditKey(event).
  function editedFilter(event, text) {
    if (event.key === Qt.Key_U) return ""                        // Ctrl+U: clear
    if (event.modifiers & Qt.ControlModifier)                    // Ctrl+Backspace: word
      return text.replace(/\s+$/, "").replace(/\S+$/, "")
    return text.slice(0, -1)                                     // Backspace: char
  }

  // Layout normalization shared by bar config consumers
  // so the two never drift. Entries are deep-cloned to decouple from the
  // input config; consumers can mutate without leaking back to shell.json.
  function normalizeLayoutEntry(entry) {
    if (typeof entry === "string") return { id: canonicalWidgetId(entry) }
    if (isPlainObject(entry) && entry.id) {
      var copy = cloneJson(entry)
      copy.id = canonicalWidgetId(copy.id)
      return copy
    }
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
