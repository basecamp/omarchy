import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Themed keyboard-shortcut hint card, callable by any process via
// `omarchy-legend` (see bin/omarchy-legend) or directly over IPC. Modeled
// on the OSD plugin (../osd/Osd.qml) — same PanelWindow/BorderSurface/
// popups-border shape — but persistent rather than auto-hiding, since a
// legend is meant to stay up while the calling tool is showing hints, not
// flash on a single state change.
Item {
  id: root

  property bool opened: false
  property var entries: [] // [[key, action], ...]
  property string corner: "top-right" // top-left | top-right | bottom-left | bottom-right

  readonly property int pad: Style.spacing.popupPadding
  readonly property int columnGap: Style.spacing.xxl
  readonly property int rowHeight: Style.spacing.popupRowHeight

  FontMetrics {
    id: fm
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  readonly property int keyColumnWidth: {
    var w = 0
    for (var i = 0; i < root.entries.length; i++)
      w = Math.max(w, Math.ceil(fm.advanceWidth(String(root.entries[i][0] || ""))))
    return w
  }
  readonly property int actionColumnWidth: {
    var w = 0
    for (var i = 0; i < root.entries.length; i++)
      w = Math.max(w, Math.ceil(fm.advanceWidth(String(root.entries[i][1] || ""))))
    return w
  }
  readonly property int contentWidth: root.keyColumnWidth + root.columnGap + root.actionColumnWidth
  readonly property int contentHeight: root.entries.length * root.rowHeight

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      entries = Array.isArray(p.entries) ? p.entries : []
      corner = (typeof p.corner === "string" && p.corner.length > 0) ? p.corner : "top-right"
      opened = entries.length > 0
    } catch (e) {}
  }

  function close() { opened = false }

  IpcHandler {
    target: "legend"
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-legend"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only surface: keep the layer-shell input region empty so the
    // legend never blocks clicks to the desktop (or the calling tool's own
    // overlay) below it.
    mask: Region {}

    BorderSurface {
      id: card
      width: card.borderLeft + root.pad + root.contentWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + root.contentHeight + root.pad + card.borderBottom
      anchors.top: root.corner.indexOf("top") === 0 ? parent.top : undefined
      anchors.bottom: root.corner.indexOf("bottom") === 0 ? parent.bottom : undefined
      anchors.left: root.corner.indexOf("left") !== -1 ? parent.left : undefined
      anchors.right: root.corner.indexOf("right") !== -1 ? parent.right : undefined
      anchors.margins: Style.space(14)
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: card.borderTop + root.pad
        anchors.leftMargin: card.borderLeft + root.pad

        Repeater {
          model: root.entries
          delegate: Row {
            width: root.contentWidth
            height: root.rowHeight
            spacing: root.columnGap

            Text {
              width: root.keyColumnWidth
              anchors.verticalCenter: parent.verticalCenter
              text: modelData[0] || ""
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: root.actionColumnWidth
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.length > 1 ? modelData[1] : ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
