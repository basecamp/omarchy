import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string icon: ""
  property string message: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true

  function clamp(v, min, max) { return Math.max(min, Math.min(max, v)) }

  function iconFor(name, percent) {
    var n = String(name || "").toLowerCase()
    if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return "󰝟"
    if (n === "volume-low") return ""
    if (n === "volume-medium") return ""
    if (n === "volume-high" || n === "volume") return ""
    if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "󰍭"
    if (n === "microphone" || n === "mic") return "󰍬"
    if (n === "keyboard") return "󰌌"
    if (n === "brightness" || n === "display") return "󰃠"
    if (n === "touchpad") return "󰟸"
    if (n === "touch" || n === "touchscreen") return "󰜉"
    if (n === "media" || n === "player") return "󰝚"
    if (percent <= 0) return "󰝟"
    if (percent <= 33) return ""
    if (percent <= 66) return ""
    return ""
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText) {
    maxValue = Math.max(1, parseInt(rawMax || "100", 10))
    var parsed = parseInt(rawValue || "0", 10)
    hasProgress = rawValue !== "" && !isNaN(parsed) && rawMessage === ""
    value = hasProgress ? clamp(parsed, 0, maxValue) : 0
    message = String(rawMessage || (hasProgress ? (rawProgressText || Math.round(value * 100 / maxValue) + "%") : ""))
    icon = iconFor(iconName, hasProgress ? Math.round(value * 100 / maxValue) : -1)
    opened = true
    hideTimer.restart()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "")
    } catch (e) {}
  }

  function close() { opened = false }

  Timer {
    id: hideTimer
    interval: 1200
    onTriggered: root.opened = false
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: card
      width: 269
      height: 68
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 67
      color: Color.alpha(Color.background, 0.97)
      border.color: Color.foreground
      border.width: 2
      radius: 0
      opacity: root.opened ? 1 : 0

      Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 16
        Text {
          width: 28
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: root.icon
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 27
          color: Color.foreground
        }
        Rectangle {
          visible: root.hasProgress
          width: visible ? 142 : 0
          height: 6
          anchors.verticalCenter: parent.verticalCenter
          color: Color.alpha(Color.foreground, 0.45)
          Rectangle {
            height: parent.height
            width: parent.width * (root.hasProgress ? root.value / root.maxValue : 0)
            color: Color.accent
          }
        }
        Text {
          width: root.hasProgress ? 41 : 190
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font.family: "JetBrainsMono Nerd Font"
          font.bold: true
          font.pixelSize: 14
          color: Color.foreground
          elide: Text.ElideRight
          maximumLineCount: 1
          clip: true
        }
      }
    }
  }
}
