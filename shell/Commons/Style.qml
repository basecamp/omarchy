pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared structural style tokens for the shell. Color is the palette
// singleton; Style holds the *shape* and *focus-affordance* tokens that
// every panel surface and qs.Ui component should bind to so they stay
// in sync as the user toggles round/sharp corners or as themes change.
//
// `cornerRadius` mirrors Hyprland's `decoration:rounding`. Themes ship
// their own rounding via theme/hyprland.lua; the user toggle via
// `omarchy style corners <round|sharp>` flips Hyprland's flag file
// and Hyprland's auto-reload pushes the new value out. The shell picks
// up the change here by re-running `hyprctl getoption` whenever either
// of those input files changes.
//
// Single source of truth lives in Hyprland; the shell follows. That
// means a theme that ships `rounding = 10` gives us 10px panels by
// default, and the round/sharp user toggle still works on top of it.
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

  property Process hyprctlProc: Process {
    id: hyprctlProc
    command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRoundingJson(text)
    }
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
  // symlink; that's when theme/hyprland.lua's `rounding` value changes.
  property FileView themeNameFile: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshTimer.restart()
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

  Component.onCompleted: refresh()
}
