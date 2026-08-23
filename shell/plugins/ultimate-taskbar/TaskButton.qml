import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var bar: null
  property var hostWindow: null
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
    var activeIndex = -1
    var i
    for (i = 0; i < windows.length; i++) {
      if (windowService.isActive(windows[i].address)) {
        activeIndex = i
        break
      }
    }
    if (activeIndex >= 0)
      windowService.activate(windows[(activeIndex + 1) % windows.length].address)
    else
      windowService.activate(windows[0].address)
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: Tokens.radius.small
    color: mouse.pressed ? bar.chromePressed
      : mouse.containsMouse ? bar.chromeHover
      : root.active ? bar.chromeActive
      : "transparent"

    Rectangle {
      visible: root.running
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: 2
      width: root.active ? 16 : (windows.length > 1 ? 12 : 8)
      height: 2
      radius: 1
      color: bar.chromeGlow
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
      font.family: "sans-serif"
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(event) {
      peekTimer.stop()
      peek.visible = false
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
    onContainsMouseChanged: {
      if (mouse.containsMouse && root.running && !menu.visible) peekTimer.restart()
      else {
        peekTimer.stop()
        peek.visible = false
      }
    }
  }

  Timer {
    id: peekTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (mouse.containsMouse && root.running && !menu.visible)
        peek.visible = true
    }
  }

  PopupWindow {
    id: peek
    visible: false
    color: "transparent"
    implicitWidth: 220
    implicitHeight: peekCol.implicitHeight + 16
    anchor.window: root.hostWindow
    anchor.item: root
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Top | Edges.Right
    anchor.rect.y: -8

    Rectangle {
      anchors.fill: parent
      color: Tokens.surface.glass
      radius: Tokens.radius.medium
      border.color: Tokens.border.subtle
      border.width: 1

      Column {
        id: peekCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 6

        Text {
          width: peekCol.width
          text: root.label
          color: Tokens.text.primary
          font.pixelSize: Style.font.body
          font.family: "sans-serif"
          elide: Text.ElideRight
        }

        Repeater {
          model: windows
          delegate: Item {
            width: peekCol.width
            height: 28

            Rectangle {
              anchors.fill: parent
              radius: Tokens.radius.small
              color: rowMouse.containsMouse ? bar.chromeHover : "transparent"
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 6
              anchors.right: peekClose.left
              anchors.rightMargin: 4
              text: (modelData.title || modelData.appId || "Window") + (modelData.minimized ? " (minimized)" : "")
              color: Tokens.text.primary
              font.pixelSize: Style.font.bodySmall
              font.family: "sans-serif"
              elide: Text.ElideRight
            }

            Text {
              id: peekClose
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: 6
              text: "×"
              color: Tokens.text.primary
              font.pixelSize: Style.font.body
              font.family: "sans-serif"
              visible: windowService ? true : false
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (windowService) windowService.activate(modelData.address)
                peek.visible = false
              }
            }

            MouseArea {
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              width: 22
              height: parent.height
              z: 2
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (windowService) windowService.close(modelData.address)
                peek.visible = false
              }
            }
          }
        }
      }
    }
  }

  PopupWindow {
    id: menu
    visible: false
    color: "transparent"
    implicitWidth: 160
    implicitHeight: col.implicitHeight + 12
    anchor.window: root.hostWindow
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
              font.family: "sans-serif"
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
