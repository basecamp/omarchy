import QtQuick

Rectangle {
  property bool hasCursor: false
  property color foreground: Color.foreground
  property real cursorOpacity: 0.10

  color: hasCursor ? Color.alpha(foreground, cursorOpacity) : "transparent"
  radius: 7
}
