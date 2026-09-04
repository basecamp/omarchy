import QtQuick

Item {
  id: root

  property string title: ""
  property string meta: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property Component trailingControl: null
  property Component iconComponent: null
  property real iconOpacity: 1
  property real metaOpacity: 0.65
  property bool uppercaseMeta: false
  property bool boldMeta: false
  property real metaLetterSpacing: 0
  property real iconSize: 40
  property real minimumHeight: 64
  property real labelSpacing: 0
  property real labelLeftMargin: 8

  implicitHeight: Math.max(minimumHeight, labels.implicitHeight)

  Loader {
    id: icon
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: root.iconSize
    height: root.iconSize
    opacity: root.iconOpacity
    sourceComponent: root.iconComponent
  }

  Column {
    id: labels
    anchors.left: icon.right
    anchors.leftMargin: root.labelLeftMargin
    anchors.right: trailing.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.labelSpacing

    Text {
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.bold: true
      font.pixelSize: Style.font.title
      textFormat: Text.PlainText
    }
    Text {
      objectName: "metaText"
      visible: root.meta !== ""
      text: root.uppercaseMeta ? root.meta.toUpperCase() : root.meta
      color: root.foreground
      opacity: root.metaOpacity
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: root.boldMeta
      font.letterSpacing: root.metaLetterSpacing
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
