import QtQuick
import qs.Commons

// Shared visual chrome for keyboard-and-mouse-navigable items inside a panel.
// Contract: items must NOT read `containsMouse` for color/border. Pointer
// enter claims the panel cursor at the root; pointer leave releases it
// (including a keyboard selection) when this item still owns the cursor.
// Visuals derive from `hasCursor` / `current`. That keeps a single
// highlight, and leaving a row clears it. Use Cursor.applyHover from
// `hovered(bool)` or a row MouseArea's containsMouse.
//
// Cursor paint is always the shared hover-cursor fill plus optional
// hover-cursor border. `outline` remains as a compatibility flag for
// callers that used to request border-only rows, but slider rows still
// receive the same hover-cursor background as every other row.
BorderSurface {
  id: root

  property bool hasCursor: false
  property bool current: false
  readonly property alias containsMouse: pointer.containsMouse

  signal hovered(bool isHovered)
  property bool outline: false
  property bool bordered: false

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color fill: Style.hoverFillFor(foreground, accent)
  property color currentFill: Style.selectedFillFor(foreground, accent)

  radius: Style.cornerRadius

  color: hasCursor ? fill : (current ? currentFill : "transparent")
  borderSpec: root.hasCursor
    ? Border.controlSpec("hover-cursor", root.foreground, root.accent)
    : (root.current
      ? Border.controlSpec("selected", root.foreground, root.accent)
      : (root.bordered
        ? Border.controlSpec("normal", root.foreground, root.accent)
        : Border.none()))

  Behavior on color {
    ColorAnimation { duration: 60 }
  }

  // acceptedButtons: NoButton so nested click MouseAreas still receive
  // presses. containsMouse still tracks pointer enter/leave on this row.
  MouseArea {
    id: pointer
    anchors.fill: parent
    z: -1
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: root.hovered(containsMouse)
  }
}
