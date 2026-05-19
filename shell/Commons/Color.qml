pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single source of truth for shell color surfaces. Top-level tokens
// (foreground/background/accent/urgent) come from the theme's colors.toml.
// Per-surface roles (Color.bar.*, Color.popups.*, Color.tooltip.*,
// Color.notifications.*, Color.menu.*, Color.appLauncher.*,
// Color.imagePicker.*) come from shell.toml, which is generated
// per theme from default/themed/shell.toml.tpl (or shipped directly by a
// theme to override). Surfaces that don't appear in shell.toml fall back to
// the foundational palette, so themes can ship partial overrides.
QtObject {
  id: root

  // Foundational palette. Live updated from theme/colors.toml.
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"

  // Flat dictionary of "section.key" -> "#rrggbb" parsed from shell.toml.
  // Reassigning this whole property is what makes surface bindings below
  // re-evaluate when the theme swaps; mutating it in place would not.
  property var shellValues: ({})

  function pick(key, fallback) {
    var v = shellValues[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  function pickAlpha(key, fallback) {
    var v = shellValues[key]
    if (typeof v !== "string" || v.length === 0) return fallback
    var n = Number(v)
    if (!isFinite(n)) return fallback
    return Math.max(0, Math.min(1, n))
  }

  function alpha(c, opacity) {
    if (!c) return Qt.rgba(0, 0, 0, opacity)
    // pick() returns raw strings from shell.toml; convert to a color object
    // so .r/.g/.b are defined. Color objects pass through unchanged.
    if (typeof c === "string") c = Qt.color(c)
    return Qt.rgba(c.r, c.g, c.b, opacity)
  }

  // Compose a color from a base-color key and its `-alpha` companion,
  // applying the alpha to the resolved color. Used by every surface that
  // exposes an alpha companion so consumers can read a single ready-to-use
  // value rather than composing themselves.
  function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
    return alpha(pick(colorKey, colorFallback), pickAlpha(alphaKey, alphaFallback))
  }

  // Surface roles. Each property reads its shell.toml override if set,
  // otherwise falls back to a foundational palette token. Color values are
  // pre-composed with their `-alpha` companion where one exists, so
  // consumers can drop them straight into a Rectangle.color binding.
  readonly property QtObject bar: QtObject {
    property color background: root.composed("bar.background", "bar.background-alpha", root.background, 1.0)
    property color text: root.pick("bar.text", root.foreground)
    property color active: root.pick("bar.active", root.urgent)
  }
  readonly property QtObject popups: QtObject {
    property color background: root.composed("popups.background", "popups.background-alpha", root.background, 1.0)
    property color text: root.pick("popups.text", root.foreground)
    property color border: root.composed("popups.border", "popups.border-alpha", root.pick("notifications.border", root.accent), 1.0)
  }
  readonly property QtObject tooltip: QtObject {
    // Default background-alpha 0.97 matches the legacy tooltip opacity so
    // existing themes look identical until they override it.
    property color background: root.composed("tooltip.background", "tooltip.background-alpha", root.background, 0.97)
    property color text: root.pick("tooltip.text", root.foreground)
    property color border: root.composed("tooltip.border", "tooltip.border-alpha", root.foreground, 1.0)
  }
  readonly property QtObject notifications: QtObject {
    property color background: root.composed("notifications.background", "notifications.background-alpha", root.background, 1.0)
    property color text: root.pick("notifications.text", root.foreground)
    property color border: root.composed("notifications.border", "notifications.border-alpha", root.accent, 1.0)
    property color countdown: root.pick("notifications.countdown", root.accent)
  }
  readonly property QtObject appLauncher: QtObject {
    property color background: root.composed("app-launcher.background", "app-launcher.background-alpha", root.background, 0.95)
    property color text: root.pick("app-launcher.text", root.foreground)
    property color border: root.composed("app-launcher.border", "app-launcher.border-alpha", root.foreground, 1.0)
    property color selectedBackground: root.composed("app-launcher.selected-background", "app-launcher.selected-background-alpha", root.foreground, 0.08)
    property color selectedText: root.pick("app-launcher.selected-text", root.accent)
    property color selectedBorder: root.composed("app-launcher.selected-border", "app-launcher.selected-border-alpha", root.foreground, 0.0)
  }
  readonly property QtObject menu: QtObject {
    // Defaults mirror the panel cursor: a subtle foreground-tint fill,
    // no visible border, accent text. Themes override any of these
    // (including the alpha companions) per surface.
    property color background: root.composed("menu.background", "menu.background-alpha", root.background, 1.0)
    property color text: root.pick("menu.text", root.foreground)
    property color border: root.composed("menu.border", "menu.border-alpha", root.foreground, 1.0)
    property color selectedBackground: root.composed("menu.selected-background", "menu.selected-background-alpha", root.pick("menu.selected", root.foreground), 0.08)
    property color selectedText: root.pick("menu.selected-text", root.accent)
    property color selectedBorder: root.composed("menu.selected-border", "menu.selected-border-alpha", root.foreground, 0.0)
  }
  readonly property QtObject imagePicker: QtObject {
    // Defaults reflect what the picker hard-coded before alphas were
    // themable: scrim background at 0.5, unselected carousel borders at
    // 0.28, selected border fully opaque.
    property color background: root.composed("image-picker.background", "image-picker.background-alpha", root.background, 0.5)
    property color text: root.pick("image-picker.text", root.foreground)
    property color selectedBorder: root.composed("image-picker.selected-border", "image-picker.selected-border-alpha", root.accent, 1.0)
    property color unselectedBorder: root.composed("image-picker.unselected-border", "image-picker.unselected-border-alpha", root.foreground, 0.28)
  }

  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var foundAccent = false
    var color4Value = ""
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "foreground") foreground = match[2]
      else if (match[1] === "background") background = match[2]
      // Prefer the explicit `accent` key; only fall back to color4 when the
      // theme doesn't define a separate accent. Aether/oodle/etc define both,
      // and color4 appears later in the file so the old single-property
      // approach was clobbering accent with color4 (#8274fd purple).
      else if (match[1] === "accent") { accent = match[2]; foundAccent = true }
      else if (match[1] === "color4") color4Value = match[2]
      else if (match[1] === "red" || match[1] === "color1") urgent = match[2]
    }
    if (!foundAccent && color4Value.length > 0) accent = color4Value
  }

  // Walk shell.toml line-by-line. The file is small, so no proper TOML
  // parser. Accepts double- or single-quoted strings for colors and bare
  // numeric values (e.g. alpha companions like `selected-background-alpha
  // = 0.08`), and tolerates trailing inline comments. Numbers are kept as
  // strings here; pickAlpha() coerces and clamps when read.
  function loadShell(raw) {
    var parsed = {}
    var text = String(raw || "")
    if (text) {
      var lines = text.split("\n")
      var section = ""
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "")
        if (!line || line.charAt(0) === "#") continue
        var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
        if (sectionMatch) { section = sectionMatch[1]; continue }
        var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
        var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
        var kv = stringKv || numKv
        if (!kv || !section) continue
        parsed[section + "." + kv[1]] = kv[2]
      }
    }
    shellValues = parsed
  }

  // Startup load only. Runtime theme switches push the payload explicitly
  // through shell IPC.
  property FileView colorsFile: FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.loadColors(text())
  }
  property FileView shellFile: FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/shell.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.loadShell(text())
    onLoadFailed: root.loadShell("")
  }
}
