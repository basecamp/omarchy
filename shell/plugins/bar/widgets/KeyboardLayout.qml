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
  property string keyboardName: ""

  function refresh() {
    if (!queryProc.running) queryProc.running = true
  }

  // fcitx5 binds a virtual keyboard and takes over the seat's main flag whenever
  // it injects, but that keyboard keeps the us layout the input method gave it.
  // Stay on the keyboard we last read until a real one is active again, so the
  // label keeps tracking that keyboard's layout rather than freezing.
  function selectKeyboard(keyboards) {
    const typed = keyboards.filter(k => !String(k.name).startsWith("hl-virtual-keyboard"))
    return typed.find(k => k.main) ?? typed.find(k => k.name === root.keyboardName)
  }

  function cycleLayout() {
    if (!root.keyboardName) return
    Hyprland.dispatch("switchxkblayout " + root.keyboardName + " next")
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
          kb = root.selectKeyboard(JSON.parse(text || "{}").keyboards ?? [])
        } catch (e) {
          return
        }

        if (!kb || !kb.active_keymap) return

        root.keyboardName = String(kb.name || "")
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
