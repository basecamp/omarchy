pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Noctalia compat shim. Plugins import `qs.Commons` and reach for these
// palette tokens / helpers. Values stream from the Omarchy theme file; the
// shell wires this singleton up at startup via setHostBar()/setHostShell().
//
// We don't try to replicate Noctalia's full Material You resolver — for the
// fields plugins actually read, a flat token table is enough.
QtObject {
  id: root

  // Live updated from theme/colors.toml via the FileView below.
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"

  // Noctalia palette tokens. We map them onto our theme colors.
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
    // Anything else, treat as a literal CSS color string (the QML color type
    // does this conversion implicitly when assigned).
    return Qt.color(k)
  }

  function loadTheme(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "foreground") foreground = match[2]
      else if (match[1] === "background") background = match[2]
      else if (match[1] === "color4" || match[1] === "accent") accent = match[2]
      else if (match[1] === "red") urgent = match[2]
    }
  }

  // `omarchy-theme-set` recreates the theme/ directory via rm+mv, which kills
  // the inotify watch on colors.toml. Use theme.name (overwritten in place) as
  // a tripwire that forces a fresh reload after each swap.
  property FileView themeFile: FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadTheme(text())
    onFileChanged: reload()
  }
  property FileView themeNameFile: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: themeColorsFile.reload()
  }
}
