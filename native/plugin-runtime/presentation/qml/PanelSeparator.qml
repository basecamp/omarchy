import QtQuick

Rectangle {
  property color foreground: Color.foreground
  property real lineOpacity: 0.16

  width: parent ? parent.width : 0
  height: 1
  color: foreground
  opacity: lineOpacity
}
