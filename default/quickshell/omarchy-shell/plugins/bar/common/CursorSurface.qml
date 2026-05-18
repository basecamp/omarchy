import QtQuick

// Shared visual chrome for keyboard-and-mouse-navigable items inside a panel.
// Contract: items must NOT read `containsMouse` for color/border. Mouse
// hover updates the panel's cursor state at the root; visuals derive from
// `hasCursor` / `current`. That's what guarantees a single highlight on
// screen at any time across both keyboard and mouse interaction.
Rectangle {
  id: root

  property bool hasCursor: false
  property bool current: false

  property color foreground: "#cacccc"
  property color fill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

  radius: 4
  color: (hasCursor || current) ? fill : "transparent"
  border.width: hasCursor ? 1 : 0
  border.color: foreground

  Behavior on color {
    ColorAnimation { duration: 60 }
  }
}
