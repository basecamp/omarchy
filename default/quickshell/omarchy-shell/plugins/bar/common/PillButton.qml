import QtQuick
import QtQuick.Controls

Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property color foreground: "#cacccc"
  property color background: "transparent"
  property color hoverBackground: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  property color pressedBackground: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22)
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real fontSize: 12
  property real iconSize: 14
  property real horizontalPadding: 10
  property real verticalPadding: 6
  property bool active: false
  property color activeBackground: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

  ToolTip.visible: tooltipText !== "" && mouseArea.containsMouse
  ToolTip.text: tooltipText
  ToolTip.delay: 400

  signal clicked()
  signal rightClicked()

  implicitWidth: row.implicitWidth + horizontalPadding * 2
  implicitHeight: row.implicitHeight + verticalPadding * 2
  radius: 4
  color: mouseArea.pressed ? pressedBackground : (mouseArea.containsMouse ? hoverBackground : (active ? activeBackground : background))

  Behavior on color {
    ColorAnimation { duration: 120 }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 8

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.text !== ""
      text: root.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }
}
