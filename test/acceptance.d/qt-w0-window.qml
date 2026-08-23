import QtQuick

Window {
  id: win
  visible: true
  width: 880
  height: 560
  title: "W0-Qt"
  color: "#1b1b1b"

  Component.onCompleted: {
    Qt.application.name = "omarchy-w0-qt"
    Qt.application.displayName = "W0-Qt"
  }

  Text {
    anchors.centerIn: parent
    text: "W0 Qt"
    color: "#eeeeee"
    font.pixelSize: 24
  }
}
