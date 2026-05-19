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

  readonly property string icon: active ? "󰅶" : ""

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

  visible: active
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: false
    tooltipText: root.active ? "No sleep, lock, or screensaver" : ""
    onPressed: function() { root.toggle() }
  }
}
