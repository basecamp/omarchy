import QtQuick
import QtQuick.Controls
import qs.Commons

// Single-line text input with the kit's focus + selection styling. Inherits
// from Qt Quick Controls TextField so the underlying type's API (text,
// placeholderText, accepted, editingFinished, validator, ...) is available
// to callers without re-exposing each property.
//
// Defaults bind to qs.Commons.Color so a caller with no theme overrides
// just works; foreground / accent / selectionTint can be overridden per
// instance. activeFocus and mouse hover / panel cursor use the same
// hover-cursor defaults, so text inputs match Button, Toggle, and Dropdown.
//
// Sizing is driven by font.pixelSize + verticalPadding. The default 30px
// implicitHeight fits dialog forms; inline callers (wifi's row-embedded
// passphrase prompt) drop verticalPadding to match a 22-26px row.
TextField {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property bool password: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY

  // Panel-cursor flag. When true (and the field isn't already focused),
  // the background paints the shared hover/cursor state.
  // For mouse-enter/leave the consumer reads QQC TextField's inherited
  // `hovered` property (via onHoveredChanged) — we don't add a sibling
  // signal because the inherited property would shadow it.
  property bool hasCursor: false

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor

  echoMode: password ? TextInput.Password : TextInput.Normal
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  background: Rectangle {
    color: root._focused
      ? Style.focusFillFor(root.foreground, root.accent)
      : (root._hot
        ? Style.hoverFillFor(root.foreground, root.accent)
        : Style.normalFillFor(root.foreground, root.accent))
    border.color: root._focused
      ? Style.focusBorderFor(root.foreground, root.accent)
      : (root._hot
        ? Style.hoverBorderFor(root.foreground, root.accent)
        : Style.normalBorderFor(root.foreground, root.accent))
    border.width: root._focused
      ? Style.focusBorderWidth
      : (root._hot ? Style.hoverBorderWidth : Style.normalBorderWidth)
    radius: Style.cornerRadius
  }
}
