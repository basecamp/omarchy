import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "nightLight"
  property var settings: ({})

  property bool active: false
  property bool toolAvailable: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (root.bar) root.bar.run("omarchy-toggle-nightlight")
    refreshTimer.restart()
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["bash", "-lc", "if command -v hyprsunset >/dev/null && pgrep -x hyprsunset >/dev/null 2>&1; then echo on; elif command -v hyprsunset >/dev/null; then echo off; else echo missing; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state = String(text || "").trim()
        root.toolAvailable = state !== "missing"
        root.active = state === "on"
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 1200
    onTriggered: root.refresh()
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  visible: toolAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.active ? "󰖔" : "󰖙"
    active: root.active
    tooltipText: root.active ? "Night light on" : "Night light off"
    onPressed: function() { root.toggle() }
  }
}
