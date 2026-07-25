import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property int waitingCount: 0
  property string tooltip: ""
  property bool refreshPending: false

  active: waitingCount > 0
  activeText: "󰆍"
  inactiveText: "󰆍"
  activeTooltipText: tooltip
  inactiveTooltipText: "No Terminal Waiting"

  function refresh() {
    if (statusProc.running) refreshPending = true
    else statusProc.running = true
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

  SequentialAnimation {
    running: root.active
    loops: Animation.Infinite

    PauseAnimation { duration: 2740 }
    NumberAnimation { target: root; property: "textRotation"; to: -10; duration: 50; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: 10; duration: 70; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: -7; duration: 55; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: 7; duration: 45; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: 0; duration: 40; easing.type: Easing.OutQuad }

    onStopped: root.textRotation = 0
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

      if (root.refreshPending) {
        root.refreshPending = false
        root.refresh()
      }
    }
  }

  onPressed: function() {
    Quickshell.execDetached(["omarchy-tmux-alert", "focus"])
  }
}
