pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared structural style tokens for the shell. Color is the palette
// singleton; Style holds everything else themes can influence — corner
// rounding, gap to screen edges, state affordances, spacing, typography
// scale, and bar dimensions.
//
// `cornerRadius` mirrors Hyprland's `decoration:rounding`, and `gapsOut`
// mirrors `general:gaps_out`. Themes and user Hyprland config own those
// values; the shell picks them up by re-running `hyprctl getoption` on
// startup and after theme IPC applies a theme.
//
// Typography, spacing, and bar size come from theme/shell.toml.
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
  // The vocabulary:
  //   normal       — idle control chrome
  //   hover-cursor — mouse hover OR panel keyboard cursor (`hasCursor`)
  //   selected     — persistent chosen/current state
  //   focus        — actual Qt activeFocus, defaulting to hover-cursor
  //
  // Each state has a color token plus fill/border alphas. Color tokens
  // may be palette roles (`foreground`, `accent`, `urgent`, `background`)
  // or hex colors. Set a state's border width to 0 to drop that border.
  property var styleOverrides: ({})

  function styleRawNum(key) {
    var v = styleOverrides[key]
    var n = Number(v)
    return isFinite(n) ? n : null
  }

  function styleNum(key, fallback) {
    var n = styleRawNum(key)
    return n === null ? fallback : n
  }

  function clampAlpha(value) {
    var n = Number(value)
    if (!isFinite(n)) return 0
    return Math.max(0, Math.min(1, n))
  }

  function styleAlpha(key, fallback) {
    return clampAlpha(styleNum(key, fallback))
  }

  function styleString(key, fallback) {
    var v = styleOverrides[key]
    if (typeof v !== "string") return fallback
    v = v.replace(/^\s+|\s+$/g, "")
    return v.length > 0 ? v : fallback
  }

  readonly property string normalColorToken: styleString("normal-color", "foreground")
  readonly property string hoverColorToken: styleString("hover-cursor-color", "foreground")
  readonly property string selectedColorToken: styleString("selected-color", "foreground")
  readonly property string pressedColorToken: styleString("pressed-color", hoverColorToken)
  readonly property string focusColorToken: styleString("focus-color", hoverColorToken)
  readonly property string selectionColorToken: styleString("selection-color", "foreground")

  readonly property int normalBorderWidth: Math.max(0, Math.round(styleNum("normal-border-width", 1)))
  readonly property int hoverBorderWidth: Math.max(0, Math.round(styleNum("hover-cursor-border-width", normalBorderWidth)))
  readonly property int selectedBorderWidth: Math.max(0, Math.round(styleNum("selected-border-width", 0)))
  readonly property int focusBorderWidth: Math.max(0, Math.round(styleNum("focus-border-width", hoverBorderWidth)))

  readonly property real normalFillAlpha:    styleAlpha("normal-fill-alpha", 0.04)
  readonly property real hoverFillAlpha:     styleAlpha("hover-cursor-fill-alpha", 0.08)
  readonly property real selectedFillAlpha:  styleAlpha("selected-fill-alpha", 0.18)
  readonly property real pressedFillAlpha:   styleAlpha("pressed-fill-alpha", 0.22)
  readonly property real focusFillAlpha:     styleAlpha("focus-fill-alpha", hoverFillAlpha)
  readonly property real selectionFillAlpha: styleAlpha("selection-fill-alpha", 0.35)

  readonly property real normalBorderAlpha:   styleAlpha("normal-border-alpha", 0.4)
  readonly property real hoverBorderAlpha:    styleAlpha("hover-cursor-border-alpha", 0.25)
  readonly property real selectedBorderAlpha: styleAlpha("selected-border-alpha", 1.0)
  readonly property real focusBorderAlpha:    styleAlpha("focus-border-alpha", hoverBorderAlpha)

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

  // Convenience colors resolved against the foundational palette.
  readonly property color normalFill: normalFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color hoverFill: hoverFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color selectedFill: selectedFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color pressedFill: pressedFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color focusFillColor: focusFillFor(Color.foreground, Color.accent, Color.urgent)
  readonly property color normalBorderColor: normalBorderFor(Color.foreground, Color.accent, Color.urgent)
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
  // fractional geometry); themes can make the shell denser or roomier
  // with `[spacing] scale`, or pin individual tokens.
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

  // Clamped 11..13 by applyShellValues — some row heights remain fixed,
  // so unbounded type growth can still clip even with scalable spacing.
  property int fontBaseSize: 12

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

  // Pull typography, bar dimensions, state tokens, and spacing out of the
  // shell.toml dict that Color already parsed. Called by Color.loadShell so
  // a single parse pass feeds both singletons.
  function applyShellValues(values) {
    var fontOut = {}
    var barOut = {}
    var styleOut = {}
    var spacingOut = {}
    var nextBase = 12
    var nextSpacingScale = 1.0
    var v = values || {}
    for (var fullKey in v) {
      var dot = fullKey.indexOf(".")
      if (dot < 0) continue
      var section = fullKey.substr(0, dot)
      var key = fullKey.substr(dot + 1)
      var raw = v[fullKey]
      if (section === "font") {
        var ival = parseInt(raw, 10)
        if (!isFinite(ival)) continue
        if (key === "base-size") nextBase = ival
        else fontOut[key] = ival
      } else if (section === "bar" && (key === "size-horizontal" || key === "size-vertical")) {
        var b = parseInt(raw, 10)
        if (isFinite(b)) barOut[key] = b
      } else if (section === "spacing") {
        var fval = parseFloat(raw)
        if (!isFinite(fval)) continue
        if (key === "scale") nextSpacingScale = fval
        else spacingOut[key] = fval
      } else if (section === "controls") {
        // Strings are passed through; styleRawNum/styleString coerce on read.
        styleOut[key] = raw
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

  // `omarchy toggle window-gaps` creates/removes this flag file. Hyprland
  // reloads its config when sourced files change, then hyprctl reflects
  // the new effective value.
  property FileView windowNoGapsToggle: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/window-no-gaps.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshTimer.restart()
    onLoaded: refreshTimer.restart()
    onLoadFailed: refreshTimer.restart()
  }

  Component.onCompleted: {
    refresh()
    resolveFontFamily()
  }
}
