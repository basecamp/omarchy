import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  implicitWidth: 48
  implicitHeight: parent ? parent.height : 40

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: Tokens.radius.small
    color: mouse.pressed ? Util.alpha(Tokens.accent.primary, 0.3)
      : mouse.containsMouse ? Util.alpha(Tokens.accent.primary, 0.18)
      : "transparent"

    Text {
      anchors.centerIn: parent
      text: "\u2630"
      color: Tokens.text.primary
      font.pixelSize: Style.font.iconLarge
      font.family: Style.font.family
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.bar && root.bar.shell)
        root.bar.shell.toggle("omarchy.ultimate-start", "{}")
    }
  }
}
