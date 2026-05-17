pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single source of truth for shell color surfaces. Top-level tokens
// (foreground/background/accent/urgent) come from the theme's colors.toml.
// Per-surface roles (Color.bar.*, Color.popups.*, Color.notifications.*,
// Color.menu.*, Color.imagePicker.*) come from shell.toml, which is generated
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

  // Surface roles. Each property reads its shell.toml override if set,
  // otherwise falls back to a foundational palette token.
  readonly property QtObject bar: QtObject {
    property color background: root.pick("bar.background", root.background)
    property color text: root.pick("bar.text", root.foreground)
    property color active: root.pick("bar.active", root.urgent)
  }
  readonly property QtObject popups: QtObject {
    property color background: root.pick("popups.background", root.background)
    property color border: root.pick("popups.border", root.foreground)
  }
  readonly property QtObject notifications: QtObject {
    property color background: root.pick("notifications.background", root.background)
    property color text: root.pick("notifications.text", root.foreground)
    property color border: root.pick("notifications.border", root.accent)
    property color countdown: root.pick("notifications.countdown", root.accent)
  }
  readonly property QtObject menu: QtObject {
    property color background: root.pick("menu.background", root.background)
    property color text: root.pick("menu.text", root.foreground)
    property color selected: root.pick("menu.selected", root.accent)
  }
  readonly property QtObject imagePicker: QtObject {
    property color background: root.pick("image-picker.background", root.background)
    property color text: root.pick("image-picker.text", root.foreground)
    property color selectedBorder: root.pick("image-picker.selected-border", root.accent)
    property color unselectedBorder: root.pick("image-picker.unselected-border", root.foreground)
  }

  // Noctalia palette tokens used by the compat widgets. Mapped onto the
  // foundational palette; not exposed in shell.toml.
  readonly property color mPrimary: accent
  readonly property color mSecondary: Qt.darker(accent, 1.2)
  readonly property color mTertiary: Qt.lighter(accent, 1.3)
  readonly property color mSurface: background
  readonly property color mSurfaceVariant: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
  readonly property color mOnSurface: foreground
  readonly property color mOnSurfaceVariant: Qt.darker(foreground, 1.4)
  readonly property color mOutline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property color mHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  readonly property color mOnHover: foreground
  readonly property color mError: urgent
  readonly property color mOnError: background

  // Plugins read this to know whether to skip mid-flight transitions. We
  // don't ship theme transitions ourselves, so it's always false.
  readonly property bool isTransitioning: false

  function alpha(c, opacity) {
    if (!c) return Qt.rgba(0, 0, 0, opacity)
    return Qt.rgba(c.r, c.g, c.b, opacity)
  }

  // Noctalia's smartAlpha picks an alpha based on the host theme's perceived
  // contrast. A flat 0.6 reads acceptably across our themes; cheap, no math.
  function smartAlpha(c) {
    return alpha(c, 0.6)
  }

  // adaptiveOpacity takes a 0..1 ratio and clamps it. Plugins use it for
  // fade animations relative to a "full" opacity value.
  function adaptiveOpacity(value) {
    if (value === undefined || value === null) return 1.0
    return Math.max(0, Math.min(1, Number(value)))
  }

  // Plugins occasionally pass a color key like "accent" or "primary" via
  // their own settings. resolveColorKey returns a color; resolveColorKeyOptional
  // returns null/undefined-ish for "none".
  function resolveColorKey(key) {
    var resolved = resolveColorKeyOptional(key)
    return resolved === null ? foreground : resolved
  }

  function resolveColorKeyOptional(key) {
    var k = String(key || "").toLowerCase()
    if (!k || k === "none") return null
    switch (k) {
      case "primary": return mPrimary
      case "secondary": return mSecondary
      case "tertiary": return mTertiary
      case "surface": return mSurface
      case "surfacevariant": return mSurfaceVariant
      case "onsurface": return mOnSurface
      case "onsurfacevariant": return mOnSurfaceVariant
      case "outline": return mOutline
      case "hover": return mHover
      case "onhover": return mOnHover
      case "error": return mError
      case "onerror": return mOnError
      case "accent": return accent
      case "foreground": return foreground
      case "background": return background
      case "urgent":
      case "red": return urgent
    }
    return Qt.color(k)
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

  // Walk shell.toml line-by-line. We only need string values for color keys,
  // and the file is small, so no proper TOML parser. Accepts double- or
  // single-quoted values and tolerates trailing inline comments.
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
        var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
        if (!kv || !section) continue
        parsed[section + "." + kv[1]] = kv[2]
      }
    }
    shellValues = parsed
  }

  property bool themeReloadSuspended: false

  function suspendThemeReloads() {
    themeReloadSuspended = true
  }

  function resumeThemeReloads() {
    themeReloadSuspended = false
  }

  function reloadTheme() {
    if (themeReloadSuspended) return
    colorsFile.reload()
    shellFile.reload()
  }

  // `omarchy-theme-set` recreates the theme/ directory via rm+mv, which kills
  // the inotify watch on colors.toml. Use theme.name (overwritten in place) as
  // a tripwire that forces a fresh reload after each swap.
  property FileView colorsFile: FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadColors(text())
    onFileChanged: root.reloadTheme()
  }
  property FileView shellFile: FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadShell(text())
    onLoadFailed: root.loadShell("")
    onFileChanged: root.reloadTheme()
  }
  property FileView themeNameFile: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: root.reloadTheme()
  }
}
