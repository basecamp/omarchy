import QtQuick
import QtQuick.Controls as Controls

Item {
  id: root

  property string label: ""
  property string description: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool checked: false
  signal clicked()

  implicitWidth: 280
  implicitHeight: Math.max(control.implicitHeight, labels.implicitHeight)

  Controls.CheckBox {
    id: control
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    palette.buttonText: root.foreground
    palette.highlight: root.accent
    onClicked: root.clicked()
  }

  Column {
    id: labels
    anchors.left: control.right
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Text {
      width: parent.width
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
    }
    Text {
      visible: root.description !== ""
      width: parent.width
      text: root.description
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
    }
  }

  MouseArea {
    anchors.fill: labels
    onClicked: root.clicked()
  }
}
