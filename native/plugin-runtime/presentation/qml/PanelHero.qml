import QtQuick

Item {
  id: root

  property string title: ""
  property string meta: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property Component trailingControl: null
  property Component iconComponent: null

  implicitHeight: Math.max(64, labels.implicitHeight)

  Loader {
    id: icon
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 40
    height: 40
    sourceComponent: root.iconComponent
  }

  Column {
    id: labels
    anchors.left: icon.right
    anchors.leftMargin: 8
    anchors.right: trailing.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter

    Text {
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.bold: true
      font.pixelSize: Style.font.title
      textFormat: Text.PlainText
    }
    Text {
      text: root.meta
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }

  Loader {
    id: trailing
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: root.trailingControl
  }
}
