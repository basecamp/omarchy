import QtQuick
import qs.Commons

// Shared visual chrome for keyboard-and-mouse-navigable items inside a panel.
// Contract: items must NOT read `containsMouse` for color/border. Mouse
// hover updates the panel's cursor state at the root; visuals derive from
// `hasCursor` / `current`. That's what guarantees a single highlight on
// screen at any time across both keyboard and mouse interaction.
//
// Two cursor visuals are supported:
//
//   default (outline: false) — paint a tinted fill across the row when
//   hasCursor is true. Use for narrow text rows (wifi networks, audio
//   devices, menu items) where fill reads cleanly.
//
//   outline: true — paint an accent border instead of a fill. Use for
//   wide content rows where a fill would obscure the row's chrome
//   (slider rows in audio / monitor panels). The fill / currentFill
//   props are ignored in this mode.
Rectangle {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool outline: false

  property color foreground: Color.foreground
  property color fill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  property color currentFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

  radius: Style.cornerRadius

  color: root.outline
    ? "transparent"
    : (hasCursor ? fill : (current ? currentFill : "transparent"))

  border.color: root.outline && hasCursor ? Style.focusBorderColor : foreground
  border.width: root.outline && hasCursor ? Style.focusBorderWidth : 0

  Behavior on color {
    ColorAnimation { duration: 60 }
  }
}
