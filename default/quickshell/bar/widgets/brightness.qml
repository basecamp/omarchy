import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "brightness"
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  property int currentPercent: -1
  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  readonly property string iconGlyph: {
    if (currentPercent < 0) return ""
    if (currentPercent > 66) return "󰃠"
    if (currentPercent > 33) return "󰃟"
    return "󰃞"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: currentPercent >= 0

  function refresh() {
    if (!readProc.running) readProc.running = true
  }

  property int pendingPercent: -1

  function setBrightness(percent) {
    var clamped = Math.max(1, Math.min(100, Math.round(percent)))
    currentPercent = clamped
    pendingPercent = clamped
    writeTimer.restart()
  }

  Timer {
    id: writeTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (writeProc.running) {
        writeTimer.restart()
        return
      }
      if (pendingPercent < 0) return
      writeProc.command = ["bash", "-lc", "brightnessctl set " + pendingPercent + "% >/dev/null"]
      pendingPercent = -1
      writeProc.running = true
    }
  }

  Component.onCompleted: refresh()

  Process {
    id: readProc
    command: ["bash", "-lc", "if command -v brightnessctl >/dev/null; then echo $(( 100 * $(brightnessctl get) / $(brightnessctl max) )); fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text || "").trim(), 10)
        if (!isNaN(n)) root.currentPercent = n
      }
    }
  }

  Process { id: writeProc }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    horizontalMargin: 6.5
    tooltipText: root.currentPercent >= 0 ? "Brightness " + root.currentPercent + "%" : ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.popupOpen = false
        root.setBrightness(80)
      } else {
        root.popupOpen = !root.popupOpen
      }
    }

    onWheelMoved: function(delta) {
      var step = Number(root.setting("step", 5))
      root.setBrightness(root.currentPercent + (delta > 0 ? step : -step))
    }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 280
    contentHeight: 80

    Column {
      anchors.fill: parent
      spacing: 10

      Row {
        spacing: 10
        width: parent.width

        Text {
          text: root.iconGlyph
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 18
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: "Brightness"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 12
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: 10; height: 1 }

        Text {
          text: root.currentPercent + "%"
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: 12
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Common.Slider {
        bar: root.bar
        width: parent.width
        minimum: 1
        maximum: 100
        step: 5
        integer: true
        value: root.currentPercent

        onMoved: function(v) { root.setBrightness(v) }
      }
    }
  }
}
