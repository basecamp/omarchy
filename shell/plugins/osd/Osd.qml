import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "OsdModel.js" as OsdModel

Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200
  property bool fit: false
  readonly property int cardWidth: Style.space(269)
  readonly property int mediaCardWidth: Math.round(cardWidth * 1.5)
  readonly property int messageWidth: Style.space(190)
  readonly property int mediaMessageWidth: messageWidth + mediaCardWidth - cardWidth
  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0
  readonly property bool textOnlyOsd: root.fit && !root.hasProgress && !root.mediaOsd
  readonly property int fitMessageWidth: root.message === "" ? 0 : Math.round(messageMetrics.boundingRect.width) + Style.space(4)
  readonly property int fitCardWidth: root.message === "" || root.fitMessageWidth === 0
    ? card.borderLeft + Style.space(16) + Style.space(28) + Style.space(16) + card.borderRight
    : card.borderLeft + Style.space(16) + Style.space(28) + Style.space(16) + root.fitMessageWidth + Style.space(16) + card.borderRight

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration, rawFit) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration, rawFit)
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    fit = next.fit
    opened = true
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration), p.fit === undefined ? false : p.fit)
    } catch (e) {}
  }

  function close() { opened = false }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
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
    // Visual-only surface: keep the layer-shell input region empty so the OSD
    // never blocks clicks to the desktop below it.
    mask: Region {}

    BorderSurface {
      id: card
      width: root.textOnlyOsd ? root.fitCardWidth : (root.mediaOsd ? root.mediaCardWidth : root.cardWidth)
      height: Math.max(Style.space(68), Style.font.displayLarge + Style.spacing.panelGap)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop
        anchors.rightMargin: card.borderRight + Style.space(16)
        anchors.bottomMargin: card.borderBottom
        anchors.leftMargin: card.borderLeft + Style.space(16)
        spacing: Style.space(16)
        Text {
          width: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: root.icon
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          color: Color.popups.text
        }
        Rectangle {
          visible: root.hasProgress
          width: visible ? Style.space(142) : 0
          height: Math.max(Style.space(6), Style.spacing.sm)
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(Color.popups.text, 0.45)
          Rectangle {
            height: parent.height
            width: parent.width * (root.hasProgress ? root.value / root.maxValue : 0)
            color: Color.accent
          }
        }
        Text {
          width: root.textOnlyOsd ? root.fitMessageWidth : (root.hasProgress ? Style.space(41) : (root.mediaOsd ? root.mediaMessageWidth : root.messageWidth))
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: Style.font.title
          color: Color.popups.text
          elide: root.textOnlyOsd ? Text.ElideNone : Text.ElideRight
          maximumLineCount: 1
          clip: !root.textOnlyOsd
        }
      }
    }
  }
}
