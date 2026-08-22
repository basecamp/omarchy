import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var bar: null
  property var group: ({})
  property var windowService: bar && bar.shell ? bar.shell.windowService : null
  property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null

  readonly property var windows: group && group.windows ? group.windows : []
  readonly property bool running: windows.length > 0
  readonly property bool active: {
    if (!windowService) return false
    for (var i = 0; i < windows.length; i++) {
      if (windowService.isActive(windows[i].address)) return true
    }
    return false
  }
  readonly property string label: group && group.name ? group.name : ""
  readonly property string iconName: group && (group.icon || group.desktopId) ? (group.icon || group.desktopId) : ""

  implicitWidth: 44
  implicitHeight: parent ? parent.height : 40

  function activate() {
    if (!root.running) {
      if (root.appLibrary && group && group.desktopId)
        root.appLibrary.launch(group.desktopId, group.name)
      return
    }
    if (windows.length === 1) {
      windowService.toggleFromTaskbar(windows[0].address)
      return
    }
    for (var i = 0; i < windows.length; i++) {
      if (windowService.isActive(windows[i].address)) {
        windowService.minimize(windows[i].address)
        return
      }
    }
    windowService.restore(windows[0].address)
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: Tokens.radius.small
    color: mouse.pressed ? Util.alpha(Tokens.accent.primary, 0.28)
      : mouse.containsMouse ? Util.alpha(Tokens.accent.primary, 0.16)
      : root.active ? Util.alpha(Tokens.accent.primary, 0.22)
      : "transparent"

    Rectangle {
      visible: root.running
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: 2
      width: root.active ? 16 : (windows.length > 1 ? 12 : 8)
      height: 2
      radius: 1
      color: Tokens.accent.primary
    }

    Image {
      id: icon
      anchors.centerIn: parent
      width: 20
      height: 20
      fillMode: Image.PreserveAspectFit
      source: root.appLibrary ? root.appLibrary.iconSource(root.iconName) : ""
      visible: status === Image.Ready
    }

    Text {
      visible: icon.status !== Image.Ready
      anchors.centerIn: parent
      text: root.label ? root.label.charAt(0).toUpperCase() : "?"
      color: Tokens.text.primary
      font.pixelSize: Style.font.body
      font.family: Style.font.family
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        menu.visible = !menu.visible
        return
      }
      if (event.modifiers & Qt.ShiftModifier) {
        if (root.appLibrary && group && group.desktopId)
          root.appLibrary.launch(group.desktopId, group.name)
        return
      }
      root.activate()
    }
  }

  PopupWindow {
    id: menu
    visible: false
    color: "transparent"
    implicitWidth: 160
    implicitHeight: col.implicitHeight + 12
    anchor.window: root.QsWindow ? root.QsWindow.window : null
    anchor.item: root
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Top | Edges.Right
    anchor.rect.y: -4

    Rectangle {
      anchors.fill: parent
      color: Tokens.surface.glass
      radius: Tokens.radius.medium
      border.color: Tokens.border.subtle
      border.width: 1

      Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 2

        Repeater {
          model: [
            { label: (group && group.pinned) ? "Unpin from taskbar" : "Pin to taskbar", action: "pin" },
            { label: "Close window", action: "close" }
          ]
          delegate: Item {
            width: col.width
            height: 28
            visible: modelData.action !== "close" || root.running

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 8
              text: modelData.label
              color: Tokens.text.primary
              font.pixelSize: Style.font.body
              font.family: Style.font.family
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                if (modelData.action === "pin" && root.bar && typeof root.bar.togglePin === "function")
                  root.bar.togglePin(group)
                if (modelData.action === "close") {
                  for (var i = 0; i < windows.length; i++) windowService.close(windows[i].address)
                }
                menu.visible = false
              }
            }
          }
        }
      }
    }
  }
}
