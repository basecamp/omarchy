import QtQuick
import qs.Commons

Item {
  id: root
  property var bar: null
  implicitWidth: 6
  implicitHeight: parent ? parent.height : 40

  Rectangle {
    anchors.fill: parent
    color: mouse.containsMouse ? Tokens.accent.primary : Tokens.border.subtle
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.bar && root.bar.shell && root.bar.shell.windowService)
        root.bar.shell.windowService.toggleShowDesktop()
    }
  }
}
