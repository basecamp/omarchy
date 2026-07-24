import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property int waitingCount: 0
  property string tooltip: ""

  active: waitingCount > 0
  activeText: "󰆍"
  inactiveText: "󰆍"
  activeTooltipText: tooltip
  inactiveTooltipText: "No terminal is waiting"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function update(raw) {
    var data = extractData(raw)
    waitingCount = Number(data.count || 0)
    tooltip = String(data.tooltip || "")
  }

  Component.onCompleted: refresh()

  // Alerts can also disappear without a hook, such as when the window or its
  // session is killed while still flagged.
  Timer {
    interval: 5000
    running: root.active
    repeat: true
    onTriggered: root.refresh()
  }

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: statusProc
    command: ["omarchy-tmux-alert", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.waitingCount = 0
        root.tooltip = ""
      }
    }
  }

  onPressed: function() {
    Quickshell.execDetached(["omarchy-tmux-alert", "focus"])
  }
}
