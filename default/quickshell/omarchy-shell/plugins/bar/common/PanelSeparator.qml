import QtQuick

// 1px horizontal divider for panel sections. The alpha-on-foreground tint
// keeps the rule legible against the panel background without competing
// with text or borders.
Rectangle {
  id: root

  property color foreground: "#cacccc"
  property real strength: 0.12

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)
}
