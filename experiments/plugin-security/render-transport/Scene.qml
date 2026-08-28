import QtQuick

Item {
  width: 320
  height: 96

  Rectangle {
    anchors.fill: parent
    radius: 18
    color: "#16181d"
    border.color: "#6e9dff"

    Rectangle {
      id: pet
      width: 42
      height: 42
      radius: 14
      anchors.verticalCenter: parent.verticalCenter
      color: "#f5c2e7"

      SequentialAnimation on x {
        loops: Animation.Infinite

        NumberAnimation {
          from: 18
          to: 260
          duration: 480
          easing.type: Easing.InOutQuad
        }

        NumberAnimation {
          from: 260
          to: 18
          duration: 480
          easing.type: Easing.InOutQuad
        }
      }

      Text {
        anchors.centerIn: parent
        text: "◆"
        color: "#16181d"
        font.pixelSize: 20
      }
    }
  }
}
