import QtQuick
import qs.Commons

// Shared visual chrome for keyboard-and-mouse-navigable items inside a panel.
// Contract: items must NOT read `containsMouse` for color/border. Mouse
// hover updates the panel's cursor state at the root; visuals derive from
// `hasCursor` / `current`. That's what guarantees a single highlight on
// screen at any time across both keyboard and mouse interaction.
//
// Cursor paint is always the shared hover-cursor fill plus optional
// hover-cursor border. `outline` remains as a compatibility flag for
// callers that used to request border-only rows, but slider rows still
// receive the same hover-cursor background as every other row.
Rectangle {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool outline: false
  property bool bordered: false

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color fill: Style.hoverFillFor(foreground, accent)
  property color currentFill: Style.selectedFillFor(foreground, accent)

  radius: Style.cornerRadius

  color: hasCursor ? fill : (current ? currentFill : "transparent")

  border.color: root.hasCursor
    ? Style.hoverBorderFor(root.foreground, root.accent)
    : (root.current
      ? Style.selectedBorderFor(root.foreground, root.accent)
      : (root.bordered
        ? Style.normalBorderFor(root.foreground, root.accent)
        : "transparent"))
  border.width: root.hasCursor
    ? Style.hoverBorderWidth
    : (root.current
      ? Style.selectedBorderWidth
      : (root.bordered ? Style.normalBorderWidth : 0))

  Behavior on color {
    ColorAnimation { duration: 60 }
  }
}
