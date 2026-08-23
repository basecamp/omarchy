import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  implicitWidth: 44
  implicitHeight: parent ? parent.height : 40

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: Tokens.radius.small
    color: mouse.pressed ? bar.chromePressed
      : mouse.containsMouse ? bar.chromeHover
      : "transparent"

    Column {
      anchors.centerIn: parent
      spacing: 3
      Repeater {
        model: 2
        Row {
          spacing: 3
          Repeater {
            model: 2
            Rectangle {
              width: 7
              height: 5
              radius: 1
              color: Tokens.text.primary
              opacity: 0.85
            }
          }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
        root.bar.shell.summon("omarchy.ultimate-task-switcher", JSON.stringify({ mode: "taskView" }))
    }
  }
}
