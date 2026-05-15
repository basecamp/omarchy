import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: 8
  property int padding: 14
  property int contentWidth: 280
  property int contentHeight: 200
  property bool open: false
  // "click" — uses HyprlandFocusGrab so clicking outside dismisses the popup.
  // "hover" — passive overlay; the owning widget controls open via hover.
  property string triggerMode: "click"

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property bool containsMouse: cardHover.hovered

  function closePopout() {
    if (owner && "closePopout" in owner) owner.closePopout()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  // Keep the surface mapped through the card's fade-out animation. If we
  // unmap the moment `open` flips false, the popup commits its final frame
  // with the card still at full opacity — Hyprland holds onto that frame
  // and leaves a stale outline at the popup's last position. By waiting for
  // the inner opacity to actually reach 0, the last committed buffer is
  // transparent and the surface tears down cleanly.
  property bool _surfaceVisible: open
  visible: _surfaceVisible
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight

  onOpenChanged: {
    if (open) _surfaceVisible = true
    else hideTimer.restart()

    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  Timer {
    id: hideTimer
    interval: 160 // matches the card opacity Behavior duration with a small buffer
    onTriggered: if (!root.open) root._surfaceVisible = false
  }

  // Outside-click dismissal via Hyprland's focus grab. While `active`, input
  // is routed only to the listed windows; clicking anywhere else clears the
  // grab and we close the popup. Skipped for hover-mode popups so the cursor
  // can move freely between the trigger and the popup.
  HyprlandFocusGrab {
    active: root.open && root.triggerMode === "click"
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.closePopout()
  }

  anchor {
    id: popupAnchor
    window: anchorItem ? anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = target.height + root.margin

      if (root.bar.position === "bottom") {
        localY = -popupHeight - root.margin
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin
        localY = target.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin
        localY = target.height / 2 - popupHeight / 2
      }

      var window = target.QsWindow.window
      if (!window) return

      var point = window.contentItem.mapFromItem(target, localX, localY)
      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  Rectangle {
    id: card
    anchors.fill: parent
    color: root.bar ? root.bar.background : "#101315"
    border.color: root.bar ? root.bar.foreground : "#cacccc"
    border.width: 1
    radius: 0
    opacity: root.open ? 1.0 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.margins: root.padding
    }

    HoverHandler {
      id: cardHover
    }
  }
}
