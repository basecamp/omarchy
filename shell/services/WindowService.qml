import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// WindowService: the typed window-management capability behind the Ultimate
// taskbar, Start, and every window affordance (docs/settings-service-api.md).
// UI never runs hyprctl and never touches ToplevelManager directly; it calls
// these intent-named verbs.
//
// Windows 7 muscle memory is the API (PRODUCT_DOCTRINE.md Rule 3):
//   minimize   — window vanishes; taskbar button stays and restores on click
//   restore    — window returns where it was
//   maximize   — fills the work area, keeps the shell chrome visible
//   snapLeft/snapRight — Win+Arrow half-screen snapping for floating windows
//
// Implementation split:
// - Minimize/restore/activate/close go through Quickshell's wlr-foreign-
//   toplevel binding (ToplevelManager): composable, no compositor coupling.
// - Maximize and snap are compositor semantics with no foreign-toplevel
//   verb, so they ride hyprctl dispatch through a short-lived Process.
QtObject {
  id: root

  property string lastError: ""

  // Snapshot of live windows for taskbar models. Consumers bind and never
  // reach Hyprland or ToplevelManager themselves.
  readonly property var windows: ToplevelManager.toplevels.values
  readonly property var activeToplevel: ToplevelManager.activeToplevel

  // ------------------------------------------------------------- helpers

  function _run(args) {
    var proc = Qt.createQmlObject("import Quickshell.Io; Process {}", root, "ws-proc")
    proc.command = ["hyprctl"].concat(args)
    proc.exited = function(code) {
      if (code !== 0) root.lastError = "hyprctl " + args.join(" ") + " exited " + code
      proc.destroy()
    }
    proc.running = true
  }

  function _dispatch(request) {
    root._run(["dispatch"].concat(request.split(" ")))
  }

  function _forAddress(address) {
    var values = ToplevelManager.toplevels.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].address === address) return values[i]
    }
    return null
  }

  // ---------------------------------------------------------------- verbs

  function focus(address) {
    var win = root._forAddress(address)
    if (win) win.activate()
  }

  function close(address) {
    var win = root._forAddress(address)
    if (win) win.close()
  }

  function minimize(address) {
    var win = root._forAddress(address)
    if (!win) return
    // Foreign-toplevel minimize. Quickshell's Toplevel exposes minimize();
    // when that API is unavailable in the pinned Quickshell, fall back to
    // parking the address in a hidden workspace via Hyprland.
    if (typeof win.minimize === "function") {
      win.minimize(true)
    } else {
      root._dispatch("movetoworkspacesilent special:minimized,address:" + address)
    }
  }

  function restore(address) {
    var win = root._forAddress(address)
    if (!win) {
      // Parked in special:minimized by our fallback path above: fetch it back.
      root._dispatch("movetoworkspacesilent special:minimized,address:" + address)
      root._dispatch("focuswindow address:" + address)
      return
    }
    if (typeof win.minimize === "function") win.minimize(false)
    win.activate()
  }

  function isActive(address) {
    return root.activeToplevel !== null && root.activeToplevel.address === address
  }

  // Taskbar button contract: click active button -> minimize; click anything
  // else -> restore/focus. Exactly Windows 7 behavior.
  function toggleFromTaskbar(address) {
    if (root.isActive(address)) {
      root.minimize(address)
    } else {
      root.restore(address)
    }
  }

  function maximize(address) {
    root.focus(address)
    // fullscreen state 2 = maximized without losing bars/chrome.
    root._dispatch("fullscreen 2")
  }

  function unmaximize(address) {
    root._dispatch("fullscreen 0")
  }

  function snapLeft(address) {
    root.focus(address)
    root._snapActive("l")
  }

  function snapRight(address) {
    root.focus(address)
    root._snapActive("r")
  }

  function _snapActive(direction) {
    // Float first so half-tiling behaves like Windows snapping rather than
    // tiling-layout manipulation, then size to the exact half.
    root._dispatch("togglefloating")
    root._dispatch("resizeactive exact 50% 100%")
    root._dispatch("movecursortocorner " + (direction === "l" ? "0" : "2"))
  }

  // Show Desktop (Win+D equivalent): minimize everything visible; the next
  // call brings the same batch home.
  property bool _desktopShown: false
  property var _batch: []

  function toggleShowDesktop() {
    if (root._desktopShown) {
      for (var i = 0; i < root._batch.length; i++) root.restore(root._batch[i])
      root._batch = []
    } else {
      var values = ToplevelManager.toplevels.values
      for (var j = 0; j < values.length; j++) {
        root._batch.push(values[j].address)
        root.minimize(values[j].address)
      }
    }
    root._desktopShown = !root._desktopShown
  }
}
