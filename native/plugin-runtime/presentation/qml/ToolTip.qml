import QtQuick

Rectangle {
  id: root

  property string text: ""
  property bool shown: false

  visible: shown && text !== ""
  z: 1000
  width: Math.min(320, label.implicitWidth + 16)
  height: label.implicitHeight + 10
  radius: 5
  color: "#202631"
  border.color: Color.alpha(Color.foreground, 0.18)
  border.width: 1

  Text {
    id: label
    anchors.centerIn: parent
    width: Math.min(304, implicitWidth)
    text: root.text
    color: Color.foreground
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
    elide: Text.ElideRight
  }
}
