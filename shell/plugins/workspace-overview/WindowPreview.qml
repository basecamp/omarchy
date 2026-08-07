import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property var toplevel

  readonly property var waylandToplevel: toplevel ? toplevel.wayland : null
  readonly property bool activatable: waylandToplevel !== null || (toplevel && String(toplevel.address || "") !== "")
  readonly property bool movable: toplevel !== null && String(toplevel.address || "") !== ""
  readonly property bool dragging: dragProxy.dragSessionActive
  readonly property string appId: waylandToplevel ? String(waylandToplevel.appId || "") : ""
  readonly property string title: toplevel ? String(toplevel.title || appId || "Window") : "Window"
  readonly property var desktopEntry: {
    if (!appId) return null
    return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId)
  }
  readonly property string iconSource: {
    if (!desktopEntry || !desktopEntry.icon) return ""
    return Quickshell.iconPath(desktopEntry.icon, true)
  }
  readonly property real titleHeight: Math.min(height * 0.3,
    Math.max(Style.space(28), Style.font.bodySmall + Style.spacing.controlPaddingY * 2))

  signal activated()
  signal dragStarted(var toplevel)
  signal dragFinished(var toplevel)

  radius: Style.cornerRadius
  color: previewHover.hovered || dragging
    ? Style.hoverFillFor(Color.menu.text, Color.accent)
    : Util.alpha(Color.background, 0.52)
  borderSpec: previewHover.hovered
    ? Border.controlSpec("hover-cursor", Color.menu.text, Color.accent)
    : Border.flat(Util.alpha(Color.menu.border, 0.32), Math.max(1, Style.normalBorderWidth))
  clip: true
  opacity: dragging ? 0.58 : 1

  Behavior on color {
    ColorAnimation { duration: 60 }
  }

  Behavior on opacity {
    NumberAnimation { duration: 60 }
  }

  Item {
    id: imageArea
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: titleBar.top
    clip: true

    ScreencopyView {
      id: preview
      anchors.centerIn: parent
      captureSource: root.waylandToplevel
      live: false
      paintCursor: false
      width: {
        if (!hasContent || sourceSize.width <= 0 || sourceSize.height <= 0) return parent.width
        return Math.min(parent.width, parent.height * sourceSize.width / sourceSize.height)
      }
      height: {
        if (!hasContent || sourceSize.width <= 0 || sourceSize.height <= 0) return parent.height
        return Math.min(parent.height, parent.width * sourceSize.height / sourceSize.width)
      }
      visible: hasContent
    }

    Image {
      visible: !preview.hasContent && source !== ""
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height) * 0.34
      height: width
      source: root.iconSource
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      opacity: 0.72
    }
  }

  Rectangle {
    id: titleBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: root.titleHeight
    color: Util.alpha(Color.menu.background, 0.92)

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      spacing: Style.spacing.sm

      Image {
        id: appIcon
        visible: source !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Style.font.icon : 0
        height: width
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (appIcon.visible ? appIcon.width + parent.spacing : 0)
        text: root.title
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  HoverHandler {
    id: previewHover
    cursorShape: root.dragging ? Qt.ClosedHandCursor
      : (root.activatable || root.movable ? Qt.PointingHandCursor : Qt.ArrowCursor)
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    enabled: root.activatable
    onTapped: root.activated()
  }

  DragHandler {
    id: previewDrag
    acceptedButtons: Qt.LeftButton
    enabled: root.movable
    target: null
    dragThreshold: Style.space(6)

    onActiveChanged: {
      if (active) {
        dragProxy.dragSessionActive = true
        root.dragStarted(root.toplevel)
      } else if (dragProxy.dragSessionActive) {
        dragProxy.Drag.drop()
        dragProxy.dragSessionActive = false
        root.dragFinished(root.toplevel)
      }
    }
  }

  Item {
    id: dragProxy
    property bool dragSessionActive: false
    property real lastX: 0
    property real lastY: 0

    x: previewDrag.active ? previewDrag.centroid.position.x : lastX
    y: previewDrag.active ? previewDrag.centroid.position.y : lastY
    width: 1
    height: 1
    onXChanged: if (previewDrag.active) lastX = x
    onYChanged: if (previewDrag.active) lastY = y
    Drag.active: dragSessionActive
    Drag.source: root
    Drag.keys: ["omarchy-window"]
    Drag.supportedActions: Qt.MoveAction
    Drag.proposedAction: Qt.MoveAction
  }
}
