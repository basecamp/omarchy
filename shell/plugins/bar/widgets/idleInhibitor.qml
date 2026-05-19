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
    command: ["bash", "-lc", "omarchy-shell idle status 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        try {
          var parsed = JSON.parse(raw)
          root.active = parsed && parsed.enabled === false
        } catch (e) {
          root.active = false
        }
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
    tooltipText: root.active ? "No lock or screensaver" : ""
    onPressed: function() { root.toggle() }
  }
}
