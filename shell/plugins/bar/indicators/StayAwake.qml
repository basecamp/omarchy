import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: "Allow Idle Lock & Screensaver"
  inactiveTooltipText: "Stay Awake"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (root.bar) root.bar.run("omarchy-toggle-idle")
    refreshTimer.restart()
  }

  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: statusProc
    command: ["omarchy-toggle-idle", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = root.extractData(text)
        root.active = data && data.enabled === true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.active = false
    }
  }

  Timer {
    id: refreshTimer
    interval: 1500
    onTriggered: root.refresh()
  }

  onPressed: function() { root.toggle() }
}
