import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property color borderColor: Color.popups.border
  property bool open: false
  property bool centerOnBar: false
  // "click" — uses HyprlandFocusGrab so clicking outside dismisses the popup.
  // "hover" — passive overlay; the owning widget controls open via hover.
  property string triggerMode: "click"

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: cardHover.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.padding * 2, (Number(implicitHeight) || 0) + root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight

  onOpenChanged: {
    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // Outside-click dismissal via Hyprland's focus grab. While `active`, input
  // is routed only to the listed windows; clicking anywhere else clears the
  // grab and we close the popup. Skipped for hover-mode popups so the cursor
  // can move freely between the trigger and the popup.
  HyprlandFocusGrab {
    active: root.open && root.triggerMode === "click"
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
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

      if (root.centerOnBar) {
        var cx = 0;
        var cy = 0;
        if (root.bar.position === "top" || root.bar.position === "bottom") {
          cx = window.width / 2 - popupWidth / 2
          cy = root.bar.position === "bottom" ? -popupHeight - root.margin : window.height + root.margin
          cx = Math.max(root.margin, Math.min(cx, window.width - popupWidth - root.margin))
        } else {
          cx = root.bar.position === "left" ? window.width + root.margin : -popupWidth - root.margin
          cy = window.height / 2 - popupHeight / 2
          cy = Math.max(root.margin, Math.min(cy, window.height - popupHeight - root.margin))
        }

        popupAnchor.rect.x = Math.round(cx)
        popupAnchor.rect.y = Math.round(cy)
        return
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)

      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
      } else {
        point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
      }

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  Rectangle {
    id: card
    anchors.fill: parent
    color: Color.popups.background
    border.color: root.borderColor
    border.width: Math.max(1, Style.space(2))
    radius: Style.cornerRadius
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
