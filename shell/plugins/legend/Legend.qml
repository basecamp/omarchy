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

  readonly property int pad: 14
  readonly property int columnGap: Style.spacing.xxl
  readonly property int rowGap: 10
  readonly property int borderWidth: Math.max(1, Style.space(2))

  function flippedCorner(c) {
    if (c === "top-right") return "top-left"
    if (c === "top-left") return "top-right"
    if (c === "bottom-right") return "bottom-left"
    if (c === "bottom-left") return "bottom-right"
    return c
  }
  // The card gets out of the cursor's way: it slides to the opposite
  // horizontal corner when the cursor is over its home slot and the other
  // slot is clear, and slides back once the cursor leaves.
  //
  // The decision is made against the two *fixed* slot rectangles (home and
  // flipped), never against where the card currently is. Feeding the card's
  // own hover/position back into the choice is a binding loop — the card
  // moves out from under the cursor, the hover clears, so it moves back —
  // so the cursor position comes only from polling the compositor
  // (`cursorProc`, every 100ms while open). A HoverHandler would be more
  // immediate but any caller can float a fullscreen overlay above this
  // surface (omaruler does) and the pointer would never reach the card
  // anyway.
  property real cursorX: 0
  property real cursorY: 0
  property bool hasCursor: false

  readonly property int edgeMargin: Style.space(14)
  readonly property int avoidPad: Style.space(20)

  function cornerRect(c) {
    var w = root.cardWidth
    var h = root.cardHeight
    var x = c.indexOf("left") !== -1 ? edgeMargin : (panel.width - w - edgeMargin)
    var y = c.indexOf("top") === 0 ? edgeMargin : (panel.height - h - edgeMargin)
    return Qt.rect(x - avoidPad, y - avoidPad, w + 2 * avoidPad, h + 2 * avoidPad)
  }
  function cursorOver(c) {
    if (!hasCursor)
      return false
    var r = cornerRect(c)
    return cursorX >= r.x && cursorX <= r.x + r.width && cursorY >= r.y && cursorY <= r.y + r.height
  }

  readonly property bool homeBlocked: cursorOver(corner)
  readonly property bool flipBlocked: cursorOver(flippedCorner(corner))
  readonly property string effectiveCorner: homeBlocked && !flipBlocked ? flippedCorner(corner) : corner

  onOpenedChanged: if (!opened) hasCursor = false

  FontMetrics {
    id: fm
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  readonly property int rowHeight: Math.ceil(fm.height)
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
    + Math.max(0, root.entries.length - 1) * root.rowGap

  // Card size derived straight from content, independent of the card item's
  // own geometry, so the slot rectangles in cornerRect() never feed the
  // card's live (possibly mid-anchor-change) width back into the flip
  // decision.
  readonly property int cardWidth: 2 * root.borderWidth + 2 * root.pad + root.contentWidth
  readonly property int cardHeight: 2 * root.borderWidth + 2 * root.pad + root.contentHeight

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

  // Hyprland reports the cursor in global layout coordinates; subtract the
  // panel's screen origin to get the panel-local position the corner rects
  // are expressed in.
  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var p = JSON.parse(text)
          if (typeof p.x === "number" && typeof p.y === "number") {
            var sx = panel.screen ? panel.screen.x : 0
            var sy = panel.screen ? panel.screen.y : 0
            root.cursorX = p.x - sx
            root.cursorY = p.y - sy
            root.hasCursor = true
          }
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 100
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: if (!cursorProc.running) cursorProc.running = true
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
    // overlay) below it. Cursor avoidance runs off polled compositor cursor
    // position, not off this surface receiving the pointer.
    mask: Region {}

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      // Positioned with x/y, not toggled anchors: switching which edge a
      // child is anchored to leaves the old anchor half-applied in this Qt
      // (the card sticks to its previous corner even after effectiveCorner
      // flips back). Plain x/y bindings always re-resolve cleanly.
      x: root.effectiveCorner.indexOf("left") !== -1
         ? root.edgeMargin
         : (parent.width - root.cardWidth - root.edgeMargin)
      y: root.effectiveCorner.indexOf("top") === 0
         ? root.edgeMargin
         : (parent.height - root.cardHeight - root.edgeMargin)
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: card.borderTop + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.rowGap

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
