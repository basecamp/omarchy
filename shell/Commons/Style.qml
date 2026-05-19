pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared structural style tokens for the shell. Color is the palette
// singleton; Style holds everything else themes can influence — corner
// rounding, state affordances, spacing, typography scale, and bar
// dimensions — so panels and qs.Ui components have a single source of
// truth.
//
// `cornerRadius` mirrors Hyprland's `decoration:rounding`. Themes ship
// their own rounding via theme/hyprland.lua; the user toggle via
// `omarchy style corners <round|sharp>` flips Hyprland's flag file
// and Hyprland's auto-reload pushes the new value out. The shell picks
// up the change here by re-running `hyprctl getoption` when theme IPC
// manually reloads the theme and whenever user toggle files change.
//
// Typography, spacing, and bar size come from `theme/shell.toml`.
// `[font] base-size` is the rem root; every `Style.font.<token>` derives
// from it via the scale multipliers below unless the theme pins that
// specific token. `[spacing] scale` multiplies shared margins, gaps, and
// padding while preserving each component's proportions. `[bar]
// size-horizontal` / `size-vertical` set the cross-axis dimension for
// top/bottom and left/right bars respectively.
QtObject {
  id: root

  property int cornerRadius: 0
  property int gapsOut: 10

  // ---------------------------------------------------------- state tokens
  //
  // Shared interactive-state tokens for every reusable surface in the kit.
  // The vocabulary is intentionally small:
  //   normal       — idle control chrome
  //   hover-cursor — mouse hover OR panel keyboard cursor (`hasCursor`)
  //   selected     — persistent chosen/current state
  //   focus        — actual Qt activeFocus, defaulting to hover-cursor
  //
  // Each state has a color token plus fill/border alphas. Color tokens may
  // be palette roles (`foreground`, `accent`, `urgent`, `background`) or
  // hex colors. Border widths are the on/off switch themes can use: set a
  // state width to 0 to remove that state border everywhere. Legacy
  // `border-width`, `idle-border-alpha`, `hover-*`, and `hot-fill-alpha`
  // remain supported aliases for existing theme shell.toml files.
  property var styleOverrides: ({})

  function keyList(keys) {
    return (typeof keys === "string") ? [keys] : keys
  }

  function styleRawNum(key) {
    var v = styleOverrides[key]
    var n = Number(v)
    return isFinite(n) ? n : null
  }

  function styleRawNumAny(keys) {
    var list = keyList(keys)
    for (var i = 0; i < list.length; i++) {
      var n = styleRawNum(list[i])
      if (n !== null) return n
    }
    return null
  }

  function styleNum(keys, fallback) {
    var n = styleRawNumAny(keys)
    return n === null ? fallback : n
  }

  function clampAlpha(value) {
    var n = Number(value)
    if (!isFinite(n)) return 0
    return Math.max(0, Math.min(1, n))
  }

  function styleAlpha(keys, fallback) {
    return clampAlpha(styleNum(keys, fallback))
  }

  function styleString(keys, fallback) {
    var list = keyList(keys)
    for (var i = 0; i < list.length; i++) {
      var v = styleOverrides[list[i]]
      if (typeof v !== "string") continue
      v = v.replace(/^\s+|\s+$/g, "")
      if (v.length > 0) return v
    }
    return fallback
  }

  readonly property string normalColorToken: styleString("normal-color", "foreground")
  readonly property string hoverColorToken: styleString(["hover-cursor-color", "hover-color"], "foreground")
  readonly property string selectedColorToken: styleString("selected-color", "foreground")
  readonly property string pressedColorToken: styleString("pressed-color", hoverColorToken)
  readonly property string focusColorToken: styleString("focus-color", hoverColorToken)
  readonly property string selectionColorToken: styleString("selection-color", "foreground")

  readonly property int normalBorderWidth: Math.max(0, Math.round(styleNum(["normal-border-width", "border-width"], 1)))
  readonly property int hoverBorderWidth: Math.max(0, Math.round(styleNum(["hover-cursor-border-width", "hover-border-width"], normalBorderWidth)))
  readonly property int selectedBorderWidth: Math.max(0, Math.round(styleNum("selected-border-width", 0)))
  readonly property int focusBorderWidth: Math.max(0, Math.round(styleNum("focus-border-width", hoverBorderWidth)))

  // Back-compat names used by older components / third-party plugins.
  readonly property int borderWidth: normalBorderWidth
  readonly property int hoverCursorBorderWidth: hoverBorderWidth

  readonly property real normalFillAlpha:       styleAlpha("normal-fill-alpha", 0.04)
  readonly property real hoverFillAlpha:        styleAlpha(["hover-cursor-fill-alpha", "hover-fill-alpha", "hot-fill-alpha"], 0.08)
  readonly property real selectedFillAlpha:     styleAlpha("selected-fill-alpha", 0.18)
  readonly property real pressedFillAlpha:      styleAlpha("pressed-fill-alpha", 0.22)
  readonly property real focusFillAlpha:        styleAlpha("focus-fill-alpha", hoverFillAlpha)
  readonly property real selectionFillAlpha:    styleAlpha("selection-fill-alpha", 0.35)

  readonly property real normalBorderAlpha:     styleAlpha(["normal-border-alpha", "idle-border-alpha"], 0.4)
  readonly property real hoverBorderAlpha:      styleAlpha(["hover-cursor-border-alpha", "hover-border-alpha"], 0.25)
  readonly property real selectedBorderAlpha:   styleAlpha("selected-border-alpha", 1.0)
  readonly property real focusBorderAlpha:      styleAlpha("focus-border-alpha", hoverBorderAlpha)

  // Back-compat names used by older components / third-party plugins.
  readonly property real idleBorderAlpha: normalBorderAlpha
  readonly property real hotFillAlpha: hoverFillAlpha
  readonly property real hoverCursorFillAlpha: hoverFillAlpha
  readonly property real hoverCursorBorderAlpha: hoverBorderAlpha

  function alpha(c, opacity) {
    var a = clampAlpha(opacity)
    if (!c) return Qt.rgba(0, 0, 0, a)
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function colorFromHex(value, fallback) {
    var s = String(value || "").replace(/^\s+|\s+$/g, "")
    var shortHex = s.match(/^#([0-9A-Fa-f]{3})$/)
    if (shortHex) {
      var sh = shortHex[1]
      return Qt.rgba(
        parseInt(sh.charAt(0) + sh.charAt(0), 16) / 255,
        parseInt(sh.charAt(1) + sh.charAt(1), 16) / 255,
        parseInt(sh.charAt(2) + sh.charAt(2), 16) / 255,
        1)
    }
    var hex = s.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/)
    if (!hex) return fallback
    var h = hex[1]
    return Qt.rgba(
      parseInt(h.substr(0, 2), 16) / 255,
      parseInt(h.substr(2, 2), 16) / 255,
      parseInt(h.substr(4, 2), 16) / 255,
      hex[2] ? parseInt(hex[2], 16) / 255 : 1)
  }

  function resolveStateColor(token, foreground, accent, urgent, fallback) {
    var fb = fallback || foreground || Color.foreground
    var s = String(token || "").replace(/^\s+|\s+$/g, "")
    var role = s.toLowerCase()
    if (role === "foreground" || role === "text") return foreground || Color.foreground
    if (role === "accent") return accent || Color.accent
    if (role === "urgent") return urgent || Color.urgent
    if (role === "background") return Color.background
    if (role === "transparent") return Qt.rgba(0, 0, 0, 0)
    return colorFromHex(s, fb)
  }

  function normalStateColor(foreground, accent, urgent) {
    return resolveStateColor(normalColorToken, foreground, accent, urgent, foreground || Color.foreground)
  }

  function hoverStateColor(foreground, accent, urgent) {
    return resolveStateColor(hoverColorToken, foreground, accent, urgent, foreground || Color.foreground)
  }

  function selectedStateColor(foreground, accent, urgent) {
    return resolveStateColor(selectedColorToken, foreground, accent, urgent, foreground || Color.foreground)
  }

  function pressedStateColor(foreground, accent, urgent) {
    return resolveStateColor(pressedColorToken, foreground, accent, urgent, hoverStateColor(foreground, accent, urgent))
  }

  function focusStateColor(foreground, accent, urgent) {
    var role = String(focusColorToken || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (role === "hover" || role === "hover-cursor" || role === "inherit")
      return hoverStateColor(foreground, accent, urgent)
    return resolveStateColor(focusColorToken, foreground, accent, urgent, hoverStateColor(foreground, accent, urgent))
  }

  function selectionStateColor(foreground, accent, urgent) {
    return resolveStateColor(selectionColorToken, foreground, accent, urgent, foreground || Color.foreground)
  }

  function normalFillFor(foreground, accent, urgent) { return alpha(normalStateColor(foreground, accent, urgent), normalFillAlpha) }
  function hoverFillFor(foreground, accent, urgent) { return alpha(hoverStateColor(foreground, accent, urgent), hoverFillAlpha) }
  function selectedFillFor(foreground, accent, urgent) { return alpha(selectedStateColor(foreground, accent, urgent), selectedFillAlpha) }
  function pressedFillFor(foreground, accent, urgent) { return alpha(pressedStateColor(foreground, accent, urgent), pressedFillAlpha) }
  function focusFillFor(foreground, accent, urgent) { return alpha(focusStateColor(foreground, accent, urgent), focusFillAlpha) }
  function selectionFillFor(foreground, accent, urgent) { return alpha(selectionStateColor(foreground, accent, urgent), selectionFillAlpha) }

  function normalBorderFor(foreground, accent, urgent) { return alpha(normalStateColor(foreground, accent, urgent), normalBorderAlpha) }
  function hoverBorderFor(foreground, accent, urgent) { return alpha(hoverStateColor(foreground, accent, urgent), hoverBorderAlpha) }
  function selectedBorderFor(foreground, accent, urgent) { return alpha(selectedStateColor(foreground, accent, urgent), selectedBorderAlpha) }
  function focusBorderFor(foreground, accent, urgent) { return alpha(focusStateColor(foreground, accent, urgent), focusBorderAlpha) }

  // Convenience colors used by panel rows and pills. `hot*` remains as a
  // compatibility alias for the hover/cursor state.
  readonly property color normalFill: normalFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color hoverFill: hoverFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color hotFill: hoverFill
  readonly property color selectedFill: selectedFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color pressedFill: pressedFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color focusFillColor: focusFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color normalBorderColor: normalBorderFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color idleBorderColor: normalBorderColor
  readonly property color hoverBorderColor: hoverBorderFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color selectedBorderColor: selectedBorderFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color focusBorderColor: focusBorderFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color selectedAccentFill: alpha(Color.accent, selectedFillAlpha)
  readonly property color selectionFill: selectionFillFor(Color.foreground, Color.accent, Color.urgent)

  // ---------------------------------------------------------- spacing
  //
  // The spacing scale is the shell equivalent of rem for margins, gaps,
  // and padding. Components keep their existing proportions by asking for
  // the old pixel value through `Style.space(px)` (or `spaceReal(px)` for
  // fractional geometry); themes can make the shell denser or roomier with
  // a single `[spacing] scale` value.
  property real spacingScale: 1.0
  property var spacingOverrides: ({})

  function spaceReal(px) {
    var n = Number(px)
    if (!isFinite(n) || n <= 0) return 0
    return n * spacingScale
  }

  function space(px) {
    var n = spaceReal(px)
    if (n <= 0) return 0
    return Math.max(1, Math.round(n))
  }

  function spacingToken(key, fallback) {
    var v = spacingOverrides[key]
    var n = Number(v)
    return (isFinite(n) && n >= 0) ? Math.round(n) : space(fallback)
  }

  readonly property QtObject spacing: QtObject {
    readonly property real scale: root.spacingScale

    readonly property int hairline: root.space(1)
    readonly property int xxs: root.spacingToken("xxs", 2)
    readonly property int xs: root.spacingToken("xs", 3)
    readonly property int sm: root.spacingToken("sm", 4)
    readonly property int md: root.spacingToken("md", 6)
    readonly property int lg: root.spacingToken("lg", 8)
    readonly property int xl: root.spacingToken("xl", 10)
    readonly property int xxl: root.spacingToken("xxl", 12)
    readonly property int xxxl: root.spacingToken("xxxl", 14)
    readonly property int huge: root.spacingToken("huge", 18)

    readonly property int controlGap: root.spacingToken("control-gap", 8)
    readonly property int controlPaddingX: root.spacingToken("control-padding-x", 10)
    readonly property int controlPaddingY: root.spacingToken("control-padding-y", 6)
    readonly property int inputPaddingY: root.spacingToken("input-padding-y", 7)
    readonly property int controlHeight: root.spacingToken("control-height", 28)
    readonly property int popupRowHeight: root.spacingToken("popup-row-height", 28)
    readonly property int dropdownWidth: root.spacingToken("dropdown-width", 240)
    readonly property int searchableDropdownWidth: root.spacingToken("searchable-dropdown-width", 260)
    readonly property int numberFieldWidth: root.spacingToken("number-field-width", 120)
    readonly property int searchablePopupMinHeight: root.spacingToken("searchable-popup-min-height", 220)
    readonly property int rowGap: root.spacingToken("row-gap", 8)
    readonly property int rowPaddingX: root.spacingToken("row-padding-x", 12)
    readonly property int labelGap: root.spacingToken("label-gap", 4)
    readonly property int panelGap: root.spacingToken("panel-gap", 14)
    readonly property int panelPadding: root.spacingToken("panel-padding", 18)
    readonly property int popupPadding: root.spacingToken("popup-padding", 14)
  }

  // ---------------------------------------------------------- typography
  //
  // `fontFamily` defaults to "monospace" so the bar and every qs.Ui
  // component follows the fontconfig alias `omarchy-font-set` writes.
  // Themes can override per-token via [font] in shell.toml, but the
  // family stays system-wide.
  property string fontFamily: "monospace"

  // The concrete family `monospace` resolves to right now, e.g.
  // "JetBrainsMono Nerd Font". Bind `font.family` to `fontFamily` (so the
  // alias path keeps working when the user runs `omarchy font set`), but
  // read `resolvedFontFamily` when you want to *display* what's drawing.
  property string resolvedFontFamily: "monospace"

  // Clamped 11..13 by loadShell — some row heights remain fixed, so
  // unbounded type growth can still clip even with scalable spacing.
  property int fontBaseSize: 12

  // Parsed maps populated by loadShell. Keep them as plain dicts so
  // reassigning the whole property fires reactive bindings. styleOverrides
  // and spacingOverrides are declared near the helpers that consume them.
  property var fontOverrides: ({})
  property var barOverrides: ({})

  function fontPx(mult) {
    return Math.max(1, Math.round(fontBaseSize * mult))
  }

  function fontToken(key, fallback) {
    var v = fontOverrides[key]
    var n = Number(v)
    return (isFinite(n) && n > 0) ? Math.round(n) : fallback
  }

  function barToken(key, fallback) {
    var v = barOverrides[key]
    var n = Number(v)
    return (isFinite(n) && n > 0) ? Math.round(n) : fallback
  }

  readonly property QtObject font: QtObject {
    readonly property string family: root.fontFamily
    readonly property string resolvedFamily: root.resolvedFontFamily
    readonly property int baseSize: root.fontBaseSize

    readonly property int caption:      root.fontToken("caption",       root.fontPx(0.833))   // 10
    readonly property int bodySmall:    root.fontToken("body-small",    root.fontPx(0.917))   // 11
    readonly property int body:         root.fontToken("body",          root.fontPx(1.0))     // 12
    readonly property int subtitle:     root.fontToken("subtitle",      root.fontPx(1.083))   // 13
    readonly property int title:        root.fontToken("title",         root.fontPx(1.167))   // 14
    readonly property int heading:      root.fontToken("heading",       root.fontPx(1.333))   // 16
    readonly property int display:      root.fontToken("display",       root.fontPx(2.0))     // 24
    readonly property int displayLarge: root.fontToken("display-large", root.fontPx(2.333))   // 28

    readonly property int iconSmall:    root.fontToken("icon-small",    bodySmall)
    readonly property int icon:         root.fontToken("icon",          title)
    readonly property int iconLarge:    root.fontToken("icon-large",    root.fontPx(1.5))     // 18
  }

  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: root.barToken("size-horizontal", 26)
    readonly property int sizeVertical:   root.barToken("size-vertical",   28)
  }

  function refresh() {
    hyprctlProc.running = true
    gapsOutProc.running = true
  }

  function scheduleRefresh() {
    refreshTimer.restart()
  }

  function applyRoundingJson(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var n = Number(json.int)
      if (isFinite(n) && n >= 0) cornerRadius = n
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }

  function applyGapsOutJson(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var css = String(json.css || "")
      var parts = css.match(/-?\d+(?:\.\d+)?/g) || []
      var n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
      if (isFinite(n) && n >= 0) gapsOut = Math.round(n)
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }

  // Parse [font] base-size + per-token overrides, [bar] size-* keys,
  // [style] state colors / alphas / border widths, and [spacing] scale +
  // token overrides out of shell.toml. Color.qml owns the quoted-string
  // side of the surface color sections; Style owns quoted strings only
  // inside [style].
  function loadShell(raw) {
    var fontOut = {}
    var barOut = {}
    var styleOut = {}
    var spacingOut = {}
    var nextBase = 12
    var nextSpacingScale = 1.0
    var text = String(raw || "")
    if (text) {
      var lines = text.split("\n")
      var section = ""
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "")
        if (!line || line.charAt(0) === "#") continue
        var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
        if (sectionMatch) { section = sectionMatch[1]; continue }
        // Accept ints/floats for numeric tokens and quoted/bare words for
        // [style] color roles / inheritance sentinels (e.g. "foreground",
        // "accent", "hover-cursor", "#c0caf5").
        var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
        var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
        var bareKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/)
        var kv = numKv || stringKv || bareKv
        if (!kv) continue
        var key = kv[1]
        var rawValue = kv[2]
        if (section === "font" && numKv) {
          var ival = parseInt(rawValue, 10)
          if (key === "base-size") nextBase = ival
          else fontOut[key] = ival
        } else if (section === "bar" && numKv && (key === "size-horizontal" || key === "size-vertical")) {
          barOut[key] = parseInt(rawValue, 10)
        } else if (section === "spacing" && numKv) {
          var fval = parseFloat(rawValue)
          if (key === "scale") nextSpacingScale = fval
          else spacingOut[key] = fval
        } else if (section === "style") {
          styleOut[key] = numKv ? parseFloat(rawValue) : rawValue
        }
      }
    }
    // Clamp the rem root. Per-token overrides aren't clamped — a theme
    // that wants display-large = 64 should be allowed to ship it.
    if (nextBase < 11) nextBase = 11
    if (nextBase > 13) nextBase = 13
    if (!isFinite(nextSpacingScale) || nextSpacingScale < 0) nextSpacingScale = 1.0
    spacingScale = nextSpacingScale
    fontBaseSize = nextBase
    fontOverrides = fontOut
    barOverrides = barOut
    spacingOverrides = spacingOut
    styleOverrides = styleOut
  }

  property Process hyprctlProc: Process {
    id: hyprctlProc
    command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRoundingJson(text)
    }
  }

  property Process gapsOutProc: Process {
    id: gapsOutProc
    command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyGapsOutJson(text)
    }
  }

  // Resolve the fontconfig alias to a concrete family name. `omarchy font
  // set <name>` rewrites ~/.config/fontconfig/fonts.conf and restarts the
  // shell, but rerun on file change anyway so manual edits propagate too.
  function resolveFontFamily() {
    fcMatchProc.running = true
  }

  property Process fcMatchProc: Process {
    id: fcMatchProc
    command: ["fc-match", "-f", "%{family[0]}", "monospace"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name.length > 0) root.resolvedFontFamily = name
      }
    }
  }

  property FileView fontconfigFile: FileView {
    path: Quickshell.env("HOME") + "/.config/fontconfig/fonts.conf"
    watchChanges: true
    printErrors: false
    onFileChanged: root.resolveFontFamily()
    onLoaded: root.resolveFontFamily()
    onLoadFailed: root.resolveFontFamily()
  }

  // Re-poll Hyprland a beat after either input file changes. Hyprland's
  // auto-reload runs asynchronously when its sourced .lua files change,
  // so racing it with an immediate hyprctl gives the old value. 200ms is
  // generous enough for Hyprland to settle without being user-visible.
  property Timer refreshTimer: Timer {
    id: refreshTimer
    interval: 200
    repeat: false
    onTriggered: root.refresh()
  }

  // `omarchy style corners <round|sharp>` and `omarchy toggle window-gaps`
  // create/remove these flag files. Hyprland reloads its config when sourced
  // files change, then hyprctl reflects the new effective values.
  property FileView roundedCornersToggle: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/rounded-corners.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshTimer.restart()
    onLoaded: refreshTimer.restart()
    onLoadFailed: refreshTimer.restart()
  }

  property FileView windowNoGapsToggle: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/window-no-gaps.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshTimer.restart()
    onLoaded: refreshTimer.restart()
    onLoadFailed: refreshTimer.restart()
  }

  property FileView shellTomlFile: FileView {
    id: shellTomlFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/shell.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.loadShell(text())
    onLoadFailed: root.loadShell("")
  }

  Component.onCompleted: {
    refresh()
    resolveFontFamily()
  }
}
