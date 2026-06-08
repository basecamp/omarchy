import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

ShellRoot {
  id: root

  property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  property var trayItem: null
  property int attempts: 0
  property string lastState: ""

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult(ok, message) {
    var payload = JSON.stringify({ ok: ok, message: String(message || "") })
    if (resultPath) {
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
    }
  }

  function findTrayItem() {
    var values = SystemTray.items.values
    var ids = []
    for (var i = 0; i < values.length; i++) {
      ids.push(String(values[i].id || ""))
      if (String(values[i].id || "") === "omarchy-test-tray") return values[i]
    }
    lastState = "items=" + ids.join(",")
    return null
  }

  function triggerSignIn() {
    var rows = menuOpener.children.values
    var labels = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      labels.push(String(row.text || ""))
      if (!row.isSeparator && String(row.text || "") === "Sign in") {
        row.triggered()
        writeResult(true, "triggered Sign in")
        return true
      }
    }
    lastState = "item=" + String(root.trayItem ? root.trayItem.id : "") + " rows=" + labels.join(",")
    return false
  }

  QsMenuOpener {
    id: menuOpener
    menu: root.trayItem ? root.trayItem.menu : null
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      root.attempts++

      if (!root.trayItem) root.trayItem = root.findTrayItem()
      if (root.trayItem && root.triggerSignIn()) {
        stop()
        return
      }

      if (root.attempts >= 50) {
        root.writeResult(false, "timed out waiting for tray menu Sign in row; " + root.lastState)
        stop()
      }
    }
  }
}
