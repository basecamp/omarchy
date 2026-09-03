import QtQuick

Rectangle {
  property bool hasCursor: false
  property color foreground: Color.foreground

  color: hasCursor ? Color.alpha(foreground, 0.10) : "transparent"
  radius: 7
}
