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
  property bool toggling: false

  readonly property int onTemp: 4000
  readonly property int offTemp: 6000

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (toggling) return
    toggling = true
    if (root.bar) root.bar.run("omarchy-toggle-nightlight")
    refreshTimer.restart()
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["bash", "-lc", "command -v hyprsunset >/dev/null || { echo missing; exit; }; if pgrep -x hyprsunset >/dev/null 2>&1; then hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -1; else echo idle; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state = String(text || "").trim()
        root.toggling = false
        if (state === "missing") {
          root.toolAvailable = false
          root.active = false
          return
        }
        root.toolAvailable = true
        var temp = parseInt(state, 10)
        root.active = !isNaN(temp) && temp < root.offTemp
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 1500
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
