import QtQuick

// PillButton that participates in a panel's single-cursor model. Use
// inside a row of pills (DNS providers, bluetooth header actions, choice
// chips) where mouse hover and keyboard cursor should land in the same
// place.
//
// Caller binds `hasCursor` to the panel's cursor state and listens to
// `hovered(bool)` to update that state when the mouse enters or leaves.
// This is structurally a wrapper around PillButton with one extra
// HoverHandler — but extracting it lets every panel use the same wiring
// idiom and lets plugin authors drop into the same cursor model without
// touching internals.
//
// Why HoverHandler instead of a MouseArea overlay: HoverHandler doesn't
// steal pointer events from PillButton's internal click MouseArea, so
// clicks still reach the underlying button. An overlay MouseArea with
// acceptedButtons: Qt.NoButton works but is fragile around tooltip
// timing and event propagation.
PillButton {
  id: root

  cursorBordered: false

  signal hovered(bool isHovered)

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
