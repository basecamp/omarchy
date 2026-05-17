import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "monitorPanel"
  property var settings: ({})

  property bool popupOpen: false
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0

  function closePopout() { popupOpen = false }

  IpcHandler {
    target: "monitorPanel"

    function brightness(percent: string): string {
      var value = Number(percent)
      root.setBrightness(value)
      return "got " + root.pendingBrightnessPercent
    }

    function state(): string {
      return JSON.stringify({
        brightness: root.brightnessPercent,
        brightnessAvailable: root.brightnessAvailable,
        focusedMonitor: root.focusedMonitor,
        scale: root.monitorScale,
        displays: root.displays
      })
    }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function setBrightness(value) {
    var percent = Math.max(1, Math.min(100, Math.round(value)))
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["bash", "-lc", "omarchy-brightness-display " + percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Math.max(1, Math.min(100, Math.round(value)))
    brightnessDebounce.restart()
  }

  function toggleMirror() {
    if (!internalMonitor || !externalMonitor) return
    actionProc.command = ["bash", "-lc", "if hyprctl monitors -j | jq -e --arg i '" + internalMonitor + "' --arg e '" + externalMonitor + "' '.[] | select(.name == $i and .mirrorOf == $e)' >/dev/null; then hyprctl keyword monitor '" + internalMonitor + ",preferred,auto,auto'; else hyprctl keyword monitor '" + internalMonitor + ",preferred,auto,auto,mirror," + externalMonitor + "'; fi"]
    if (!actionProc.running) actionProc.running = true
  }

  function toggleInternal() {
    if (!internalMonitor || !externalMonitor) return
    actionProc.command = ["bash", "-lc", "if hyprctl monitors -j | jq -e --arg i '" + internalMonitor + "' '.[] | select(.name == $i)' >/dev/null; then hyprctl keyword monitor '" + internalMonitor + ",disable'; else hyprctl keyword monitor '" + internalMonitor + ",preferred,auto,auto'; fi"]
    if (!actionProc.running) actionProc.running = true
  }

  function normalizeScale(scale) {
    var n = parseFloat(String(scale || ""))
    if (!isFinite(n)) return ""
    return String(Math.round(n * 100) / 100)
  }

  function updateDisplays(displaysJson) {
    try {
      root.displays = displaysJson ? JSON.parse(displaysJson) : []
    } catch(e) {
      root.displays = []
    }

    var count = 0
    for (var i = 0; i < root.displays.length; i++)
      if (root.displays[i] && root.displays[i].enabled) count++
    root.enabledDisplayCount = count
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return

    actionProc.command = ["hyprctl", "keyword", "monitor", name + (enabled ? ",disable" : ",preferred,auto,auto")]
    if (!actionProc.running) actionProc.running = true
  }

  function setScale(scale) {
    actionProc.command = ["bash", "-lc", "omarchy-hyprland-monitor-scaling-set " + scale]
    if (!actionProc.running) actionProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["bash", "-lc", "omarchy-brightness-display 2>/dev/null || true; monitors_json=$(hyprctl monitors all -j); printf '%s\\n' \"$monitors_json\" | jq -r 'def internal: test(\"^(eDP|LVDS|DSI)-\"); ([.[] | select(.name | internal)][0].name // \"\"), ([.[] | select((.name | internal) | not)][0].name // \"\"), ([.[] | select((.name | internal) and .disabled != true)][0].name // \"\"), ([.[] | select((.name | internal) and .mirrorOf != \"none\")][0].mirrorOf // \"\")'; omarchy-hyprland-monitor-focused 2>/dev/null || echo; omarchy-hyprland-monitor-scaling-get 2>/dev/null || echo; printf '%s\\n' \"$monitors_json\" | jq -c '[.[] | {name, enabled:(.disabled != true), focused:(.focused == true)}]'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      } else {
        root.refresh()
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍹"
    fontSize: 13
    onPressed: function(b) { root.popupOpen = !root.popupOpen }
    onWheelMoved: function(delta) {
      if (root.brightnessAvailable) root.setBrightness(root.brightnessPercent + (delta > 0 ? 5 : -5))
    }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 320
    contentHeight: panelColumn.implicitHeight + 28

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: 14

      Row {
        width: parent.width
        spacing: 8

        Text {
          text: "Display"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: root.focusedMonitor ? "· " + root.focusedMonitor : ""
          color: Qt.darker(root.bar.foreground, 1.8)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
          width: parent.width - 70
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        width: parent.width
        spacing: 8
        visible: root.brightnessAvailable

        Text {
          text: "󰃠"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 16
          width: 22
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Common.Slider {
          id: brightnessSlider
          bar: root.bar
          width: parent.width - 22 - brightnessPercent.width - 16
          anchors.verticalCenter: parent.verticalCenter
          minimum: 1
          maximum: 100
          step: 1
          value: root.brightnessPercent
          integer: true
          onMoved: function(v) { root.previewBrightness(v) }
          onReleased: function(v) {
            brightnessDebounce.stop()
            root.setBrightness(v)
          }
        }

        Text {
          id: brightnessPercent
          text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          width: 36
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        visible: !root.brightnessAvailable
        text: "No controllable backlight found"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
      }

      Column {
        width: parent.width
        spacing: 8

        Text {
          text: "Scale" + (root.monitorScale ? " · " + root.monitorScale + "x" : "")
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: 6

          ScaleButton { scaleValue: "1" }
          ScaleButton { scaleValue: "1.25" }
          ScaleButton { scaleValue: "1.6" }
          ScaleButton { scaleValue: "2" }
          ScaleButton { scaleValue: "3" }
          ScaleButton { scaleValue: "4" }
        }
      }

      Column {
        width: parent.width
        spacing: 8
        visible: root.displays.length > 0

        Text {
          text: "Monitors"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          font.bold: true
        }

        Repeater {
          model: root.displays

          ToggleRow {
            required property var modelData

            label: modelData.name + (modelData.focused ? " · focused" : "")
            checked: modelData.enabled
            enabled: !modelData.enabled || root.enabledDisplayCount > 1
            opacity: enabled ? 1.0 : 0.45
            onClicked: root.toggleDisplay(modelData.name, modelData.enabled)
          }
        }
      }
    }
  }

  component ScaleButton: Rectangle {
    property string scaleValue: ""
    readonly property bool active: root.normalizeScale(root.monitorScale) === root.normalizeScale(scaleValue)

    width: (panelColumn.width - 30) / 6
    height: 28
    radius: 0
    color: scaleArea.pressed ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.24)
      : scaleArea.containsMouse ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14)
      : active ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.20)
      : "transparent"

    Text {
      anchors.centerIn: parent
      text: scaleValue + "x"
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: 11
      font.bold: active
    }

    MouseArea {
      id: scaleArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setScale(scaleValue)
    }
  }

  component ToggleRow: Rectangle {
    property string label: ""
    property bool checked: false
    signal clicked()

    width: panelColumn.width
    height: 30
    color: area.pressed ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.22)
      : area.containsMouse ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      : "transparent"

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Text {
        text: checked ? "󰄬" : "󰄱"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 14
        width: 18
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        text: label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
        width: parent.width - 26
      }
    }

    MouseArea {
      id: area
      anchors.fill: parent
      enabled: parent.enabled
      hoverEnabled: true
      cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: parent.clicked()
    }
  }
}
