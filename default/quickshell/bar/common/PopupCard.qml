import QtQuick
import Quickshell

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

  readonly property var coordinatorKey: owner || root

  function closePopout() {
    if (owner && "closePopout" in owner) owner.closePopout()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight

  onOpenChanged: {
    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
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
  }
}
