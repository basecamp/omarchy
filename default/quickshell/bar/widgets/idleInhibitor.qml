import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "idleInhibitor"
  property var settings: ({})

  property bool active: false
  property int holdSeconds: 0

  readonly property string icon: active ? "󰛊" : "󰾪"

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
    command: ["bash", "-lc", "if pgrep -x hyprlock >/dev/null 2>&1; then echo locked; elif pgrep -f 'systemd-inhibit' >/dev/null 2>&1; then echo inhibited; elif [[ -f /tmp/omarchy-idle-off ]]; then echo off; else echo idle; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state = String(text || "").trim()
        root.active = state === "inhibited" || state === "off"
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

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.active
    tooltipText: root.active ? "Idle inhibited — click to allow sleep" : "System can idle — click to keep awake"
    onPressed: function() { root.toggle() }
  }
}
