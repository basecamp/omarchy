pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared structural style tokens for the shell. Color is the palette
// singleton; Style holds the *shape* and *focus-affordance* tokens that
// every panel surface and qs.Ui component should bind to so they stay
// in sync as the user toggles round/sharp corners or as themes change.
//
// `cornerRadius` is mirrored from ~/.local/state/omarchy/toggles/quickshell-menu.json.
// `omarchy style corners <round|sharp>` writes that file; we watch it and
// hot-reload the binding here so every consumer rerenders.
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

  // Convenience: the standard "hot" (hover or keyboard cursor) tint used by
  // PillButton, PanelActionButton, etc. Foreground at 0.12 alpha matches the
  // value PillButton was already painting before promotion.
  readonly property color hotFill: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

  function loadStyleState(raw) {
    try {
      var s = JSON.parse(raw || "{}")
      var n = Number(s.radius)
      cornerRadius = isFinite(n) ? n : 0
    } catch (e) {
      cornerRadius = 0
    }
  }

  property FileView styleStateFile: FileView {
    id: styleStateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/quickshell-menu.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadStyleState(text())
    onLoadFailed: root.loadStyleState("")
    onFileChanged: reload()
  }
}
