import QtQuick

Rectangle {
  property color foreground: Color.foreground

  width: parent ? parent.width : 0
  height: 1
  color: foreground
  opacity: 0.16
}
