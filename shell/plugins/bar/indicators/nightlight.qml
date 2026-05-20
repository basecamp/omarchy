import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property bool nightlight: false

  active: nightlight
  activeText: "󰔎"
  inactiveText: "󰔎"
  activeTooltipText: "Day Light"
  inactiveTooltipText: "Night Light"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function update(raw) {
    var data = extractData(raw)
    nightlight = data && data.enabled === true
  }

  function toggle() {
    if (root.bar) root.bar.run("omarchy-toggle-nightlight")
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
    command: ["omarchy-toggle-nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.nightlight = false
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
