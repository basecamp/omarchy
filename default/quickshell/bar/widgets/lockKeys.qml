import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "lockKeys"
  property var settings: ({})

  property bool capsOn: false
  property bool numOn: false
  property bool scrollOn: false
  property bool hideWhenOff: true

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  Component.onCompleted: {
    hideWhenOff = setting("hideWhenOff", true) === true
    refresh()
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  Process {
    id: stateProc
    command: ["bash", "-lc", "cat /sys/class/leds/input*::capslock/brightness 2>/dev/null | head -1; cat /sys/class/leds/input*::numlock/brightness 2>/dev/null | head -1; cat /sys/class/leds/input*::scrolllock/brightness 2>/dev/null | head -1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        root.capsOn = parseInt(lines[0], 10) > 0
        root.numOn = parseInt(lines[1], 10) > 0
        root.scrollOn = parseInt(lines[2], 10) > 0
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  readonly property bool anyOn: capsOn || numOn || scrollOn
  visible: hideWhenOff ? anyOn : true

  readonly property bool vertical: bar ? bar.vertical : false

  implicitWidth: vertical ? (bar ? bar.barSize : 28) : (lay.item ? lay.item.implicitWidth + 8 : 0)
  implicitHeight: vertical ? (lay.item ? lay.item.implicitHeight + 8 : 0) : (bar ? bar.barSize : 26)

  Loader {
    id: lay
    anchors.centerIn: parent
    sourceComponent: root.vertical ? colLayout : rowLayout
  }

  Component {
    id: rowLayout
    Row {
      spacing: 4
      LockGlyph { glyph: "A"; active: root.capsOn; visible: !root.hideWhenOff || root.capsOn }
      LockGlyph { glyph: "1"; active: root.numOn; visible: !root.hideWhenOff || root.numOn }
      LockGlyph { glyph: "S"; active: root.scrollOn; visible: !root.hideWhenOff || root.scrollOn }
    }
  }

  Component {
    id: colLayout
    Column {
      spacing: 2
      LockGlyph { glyph: "A"; active: root.capsOn; visible: !root.hideWhenOff || root.capsOn }
      LockGlyph { glyph: "1"; active: root.numOn; visible: !root.hideWhenOff || root.numOn }
      LockGlyph { glyph: "S"; active: root.scrollOn; visible: !root.hideWhenOff || root.scrollOn }
    }
  }

  component LockGlyph: Text {
    property string glyph: ""
    property bool active: false

    text: glyph
    color: active ? (root.bar ? root.bar.foreground : "#cacccc") : Qt.rgba(0.7, 0.7, 0.7, 0.3)
    font.family: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
    font.pixelSize: 11
  }
}
