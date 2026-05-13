pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Noctalia compat shim. Their plugins read Settings.data.* and call
// Settings.getBarPositionForScreen / getBarWidgetsForScreen. We expose a
// read-only view of our shell.json so reads succeed; writes are best routed
// through pluginApi.saveSettings() instead.
QtObject {
  id: root

  property var data: ({
    bar: {
      position: "top",
      widgets: { left: [], center: [], right: [] }
    },
    general: {},
    colorSchemes: { darkMode: true }
  })

  // Plugins use this gate around verbose debug logging. Defaulting to false
  // keeps their Logger.d calls silent unless we explicitly flip it.
  property bool isDebug: false

  // shellConfig is wired by shell.qml at startup; reading it keeps Settings.data
  // in lockstep with the live shell config.
  property var shellConfig: null
  onShellConfigChanged: rebuildData()

  function rebuildData() {
    var sc = shellConfig || {}
    var bar = (sc && sc.bar) ? sc.bar : {}
    var layout = (bar && bar.layout) ? bar.layout : {}
    data = {
      bar: {
        position: bar.position || "top",
        centerAnchor: bar.centerAnchor || "",
        fontFamily: bar.fontFamily || "JetBrainsMono Nerd Font",
        widgets: {
          left: Array.isArray(layout.left) ? layout.left : [],
          center: Array.isArray(layout.center) ? layout.center : [],
          right: Array.isArray(layout.right) ? layout.right : []
        }
      },
      general: {},
      colorSchemes: { darkMode: true }
    }
  }

  function getBarPositionForScreen(name) {
    return data && data.bar ? data.bar.position : "top"
  }

  function getBarWidgetsForScreen(name) {
    return data && data.bar ? data.bar.widgets : { left: [], center: [], right: [] }
  }

  function getScreenOverrideEntry(name) { return null }
  function hasScreenOverride(name, key) { return false }
  function setScreenOverride(name, key, value) { /* not supported */ }
}
