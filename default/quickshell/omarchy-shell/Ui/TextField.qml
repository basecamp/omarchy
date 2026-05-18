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
// ring Toggle and ChoiceButton paint) so keyboard cursor and form-focus
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

  echoMode: password ? TextInput.Password : TextInput.Normal
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
                   root.activeFocus ? 0.08 : 0.04)
    border.color: root.activeFocus
      ? Style.focusBorderColor
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
    border.width: root.activeFocus ? Style.focusBorderWidth : 1
    radius: Style.cornerRadius
  }
}
