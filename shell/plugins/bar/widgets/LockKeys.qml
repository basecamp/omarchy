import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "LockKeys"


  property bool capsOn: false
  property bool numOn: false
  property bool scrollOn: false
  property bool hideWhenOff: true

  Component.onCompleted: {
    hideWhenOff = setting("hideWhenOff", true) === true
    refresh()
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  property bool ledsAvailable: true

  Process {
    id: stateProc
    command: ["bash", "-lc", "read_led() { for path in /sys/class/leds/input*::$1; do if [[ -r $path/brightness ]]; then cat $path/brightness; return; fi; done; echo missing; }; read_led capslock; read_led numlock; read_led scrolllock"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var caps = String(lines[0] || "").trim()
        var num = String(lines[1] || "").trim()
        var scroll = String(lines[2] || "").trim()
        root.capsOn = caps !== "missing" && parseInt(caps, 10) > 0
        root.numOn = num !== "missing" && parseInt(num, 10) > 0
        root.scrollOn = scroll !== "missing" && parseInt(scroll, 10) > 0
        root.ledsAvailable = caps !== "missing" || num !== "missing" || scroll !== "missing"
      }
    }
  }

  Timer {
    interval: 2000
    running: root.ledsAvailable
    repeat: true
    onTriggered: root.refresh()
  }

  readonly property bool anyOn: capsOn || numOn || scrollOn
  visible: ledsAvailable && (hideWhenOff ? anyOn : true)

  implicitWidth: vertical ? barSize : (lay.item ? lay.item.implicitWidth + Style.spacing.controlGap : 0)
  implicitHeight: vertical ? (lay.item ? lay.item.implicitHeight + Style.spacing.controlGap : 0) : barSize

  Loader {
    id: lay
    anchors.centerIn: parent
    sourceComponent: root.vertical ? colLayout : rowLayout
  }

  Component {
    id: rowLayout
    Row {
      spacing: Style.space(4)
      LockGlyph { glyph: "A"; active: root.capsOn; visible: !root.hideWhenOff || root.capsOn }
      LockGlyph { glyph: "1"; active: root.numOn; visible: !root.hideWhenOff || root.numOn }
      LockGlyph { glyph: "S"; active: root.scrollOn; visible: !root.hideWhenOff || root.scrollOn }
    }
  }

  Component {
    id: colLayout
    Column {
      spacing: Style.space(2)
      LockGlyph { glyph: "A"; active: root.capsOn; visible: !root.hideWhenOff || root.capsOn }
      LockGlyph { glyph: "1"; active: root.numOn; visible: !root.hideWhenOff || root.numOn }
      LockGlyph { glyph: "S"; active: root.scrollOn; visible: !root.hideWhenOff || root.scrollOn }
    }
  }

  component LockGlyph: Text {
    property string glyph: ""
    property bool active: false

    text: glyph
    color: active ? (root.bar ? root.bar.foreground : Color.foreground) : Qt.rgba(0.7, 0.7, 0.7, 0.3)
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
  }
}
