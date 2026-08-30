import QtQuick

Rectangle {
  id: root
  property int presses: 0
  property int moves: 0
  property int releases: 0
  property int cancels: 0
  color: Qt.rgba(presses / 16, moves / 16, (releases + cancels) / 16, 1)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onPressed: root.presses += 1
    onPositionChanged: {
      if (mouse.buttons !== Qt.NoButton)
        root.moves += 1
    }
    onReleased: root.releases += 1
    onCanceled: root.cancels += 1
  }
}
