import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "idleInhibitor"
  property var settings: ({})

  property bool active: false

  readonly property string icon: active ? "󰅶" : "󰛊"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (root.bar) root.bar.run("omarchy-toggle-idle")
    refreshTimer.restart()
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["bash", "-lc", "pgrep -x hypridle >/dev/null 2>&1 && echo running || echo stopped"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.active = String(text || "").trim() === "stopped"
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.active
    tooltipText: root.active ? "Staying awake — click to allow idle" : "Can idle — click to stay awake"
    onPressed: function() { root.toggle() }
  }
}
