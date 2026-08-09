import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "omarchy.keyboard-layout"


  property string layoutLabel: ""
  property string layoutFull: ""

  function refresh() {
    if (!queryProc.running) queryProc.running = true
  }

  // fcitx5 binds a virtual keyboard and takes over the seat's main flag whenever
  // it injects, but that keyboard keeps the us layout the input method gave it.
  function isTypedOn(kb) {
    return kb.main && !String(kb.name).startsWith("hl-virtual-keyboard")
  }

  function cycleLayout() {
    Hyprland.dispatch("switchxkblayout current next")
    refreshTimer.restart()
  }

  Component.onCompleted: refresh()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      if (String(event.name).indexOf("activelayout") !== -1) root.refresh()
    }
  }

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let kb
        try {
          kb = JSON.parse(text || "{}").keyboards?.find(k => root.isTypedOn(k))
        } catch (e) {
          return
        }

        if (!kb || !kb.active_keymap) return

        root.layoutFull = kb.active_keymap
        root.layoutLabel = kb.active_keymap.split(/\s+/)[0].substring(0, 3).toUpperCase()
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  visible: layoutLabel !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.layoutFull
    onPressed: function() { root.cycleLayout() }
  }
}
