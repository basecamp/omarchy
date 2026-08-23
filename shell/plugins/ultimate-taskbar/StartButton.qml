import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  implicitWidth: 76
  implicitHeight: parent ? parent.height : 40

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: Tokens.radius.small
    color: mouse.pressed ? bar.chromePressed
      : mouse.containsMouse ? bar.chromeHover
      : "transparent"

    Row {
      anchors.centerIn: parent
      spacing: 6

      Grid {
        anchors.verticalCenter: parent.verticalCenter
        columns: 2
        rows: 2
        rowSpacing: 1
        columnSpacing: 1
        Repeater {
          model: 4
          Rectangle {
            width: 5
            height: 5
            color: bar.chromeStart
            opacity: 0.45 + index * 0.15
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Start"
        color: Tokens.text.primary
        font.pixelSize: Style.font.body
        font.family: "sans-serif"
      }
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
