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
// instance. Focus styling uses Style.focusBorderColor (the same accent
// ring Toggle and Button paint) so keyboard cursor and form focus
// chrome stay consistent across the shell.
//
// Sizing is driven by font.pixelSize + verticalPadding. The default 30px
// implicitHeight fits dialog forms; inline callers (wifi's row-embedded
// passphrase prompt) drop verticalPadding to match a 22-26px row.
TextField {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectionTint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35)
  property bool password: false
  property real horizontalPadding: 10
  property real verticalPadding: 7

  // Panel-cursor flag. When true (and the field isn't already focused),
  // the background paints the same accent ring as activeFocus so the
  // panel's keyboard cursor lands here identically to a mouse hover.
  // For mouse-enter/leave the consumer reads QQC TextField's inherited
  // `hovered` property (via onHoveredChanged) — we don't add a sibling
  // signal because the inherited property would shadow it.
  property bool hasCursor: false

  readonly property bool _focused: activeFocus || hasCursor

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
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                   root._focused ? 0.08 : 0.04)
    border.color: root._focused
      ? Style.focusBorderColor
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
    border.width: root._focused ? Style.focusBorderWidth : 1
    radius: Style.cornerRadius
  }
}
