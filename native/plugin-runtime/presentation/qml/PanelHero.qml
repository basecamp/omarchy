import QtQuick
Item {
  property string title: ""
  property string subtitle: ""
  property string meta: ""
  property real metaOpacity: 1
  property real iconOpacity: 1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property Component iconComponent
  implicitHeight: 72
  Loader { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; sourceComponent: parent.iconComponent; opacity: parent.iconOpacity }
  Text { anchors.centerIn: parent; text: parent.title; color: parent.foreground; font.family: parent.fontFamily; font.bold: true }
}
