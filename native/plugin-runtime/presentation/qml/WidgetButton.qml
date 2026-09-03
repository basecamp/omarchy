import QtQuick

Rectangle {
  id: root

  property var bar: null
  property string text: ""
  property bool active: false
  property string tooltipText: ""
  signal pressed(int mouseButton)
  signal wheelMoved(real delta)

  color: pointer.containsMouse ? "#243142" : "transparent"

  Text {
    anchors.centerIn: parent
    text: root.text
    color: Color.foreground
    font.pixelSize: 18
    textFormat: Text.PlainText
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    onPressed: function(mouse) { root.pressed(mouse.button) }
    onWheel: function(wheel) { root.wheelMoved(wheel.angleDelta.y) }
  }

  ToolTip {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.top
    anchors.bottomMargin: 6
    text: root.tooltipText
    shown: pointer.containsMouse
  }
}
