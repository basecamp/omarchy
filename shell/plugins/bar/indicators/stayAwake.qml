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
    target: root.bar
    ignoreUnknownSignals: true
    function onIndicatorsRefreshRequested() { root.refresh() }
  }

  Process {
    id: statusProc
    command: ["bash", "-lc", "omarchy-shell idle status 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = root.extractData(text)
        root.active = data && data.enabled === false
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 1500
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  onPressed: function() { root.toggle() }
}
