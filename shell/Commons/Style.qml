pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared structural style tokens for the shell. Color is the palette
// singleton; Style holds everything else themes can influence — corner
// rounding, focus affordances, typography scale, and bar dimensions —
// so panels and qs.Ui components have a single source of truth.
//
// `cornerRadius` mirrors Hyprland's `decoration:rounding`. Themes ship
// their own rounding via theme/hyprland.lua; the user toggle via
// `omarchy style corners <round|sharp>` flips Hyprland's flag file
// and Hyprland's auto-reload pushes the new value out. The shell picks
// up the change here by re-running `hyprctl getoption` whenever either
// of those input files changes.
//
// Typography and bar size come from `theme/shell.toml`. `[font] base-size`
// is the rem root; every `Style.font.<token>` derives from it via the
// scale multipliers below unless the theme pins that specific token.
// `[bar] size-horizontal` / `size-vertical` set the cross-axis dimension
// for top/bottom and left/right bars respectively.
QtObject {
  id: root

  property int cornerRadius: 0

  // Focus affordances. Deliberately distinct from "selected" (which uses an
  // accent fill) so the keyboard cursor never reads as the chosen value.
  // The settings panel originated these tokens; promoting them here means
  // every Ui component picks them up uniformly.
  readonly property color focusBorderColor: Color.accent
  readonly property color focusFillColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
  readonly property int focusBorderWidth: 3

  // Convenience fills used by panel rows and pills. Hot is hover/keyboard
  // cursor; selected is the persistent chosen/current item state.
  readonly property color hotFill: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
  readonly property color selectedFill: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)

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

  // Clamped 11..13 by loadShell — bar height and row heights are fixed
  // until we ship matching spacing tokens, so unbounded growth clips.
  property int fontBaseSize: 12

  // Parsed maps populated by loadShell. Keep them as plain dicts so
  // reassigning the whole property fires reactive bindings.
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

  // Parse [font] base-size + per-token overrides and [bar] size-* keys
  // out of shell.toml. Color.qml owns the quoted-string side of the same
  // file; we only care about the unquoted integer values here.
  function loadShell(raw) {
    var fontOut = {}
    var barOut = {}
    var nextBase = 12
    var text = String(raw || "")
    if (text) {
      var lines = text.split("\n")
      var section = ""
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "")
        if (!line || line.charAt(0) === "#") continue
        var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
        if (sectionMatch) { section = sectionMatch[1]; continue }
        var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+)\s*(#.*)?$/)
        if (!kv) continue
        var key = kv[1]
        var val = parseInt(kv[2], 10)
        if (section === "font") {
          if (key === "base-size") nextBase = val
          else fontOut[key] = val
        } else if (section === "bar" && (key === "size-horizontal" || key === "size-vertical")) {
          barOut[key] = val
        }
      }
    }
    // Clamp the rem root. Per-token overrides aren't clamped — a theme
    // that wants display-large = 64 should be allowed to ship it.
    if (nextBase < 11) nextBase = 11
    if (nextBase > 13) nextBase = 13
    fontBaseSize = nextBase
    fontOverrides = fontOut
    barOverrides = barOut
  }

  property Process hyprctlProc: Process {
    id: hyprctlProc
    command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRoundingJson(text)
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

  // The theme name flips whenever `omarchy-theme-set` swaps the theme/
  // symlink; that's when theme/hyprland.lua's `rounding` value changes
  // and the new theme/shell.toml drops into place. Force a reload of
  // shell.toml here so we don't wait on the inotify watch — Color.qml
  // uses the same tripwire for the same reason.
  property FileView themeNameFile: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      refreshTimer.restart()
      shellTomlFile.reload()
    }
  }

  // `omarchy style corners <round|sharp>` creates or removes this flag file.
  // Hyprland reloads its config when sourced files change, then hyprctl
  // reflects the new effective rounding value.
  property FileView roundedCornersToggle: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/rounded-corners.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshTimer.restart()
    onLoaded: refreshTimer.restart()
    onLoadFailed: refreshTimer.restart()
  }

  property FileView shellTomlFile: FileView {
    id: shellTomlFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadShell(text())
    onLoadFailed: root.loadShell("")
    onFileChanged: reload()
  }

  Component.onCompleted: {
    refresh()
    resolveFontFamily()
  }
}
