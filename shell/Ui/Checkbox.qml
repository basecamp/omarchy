import QtQuick
import qs.Commons

// Labeled checkbox. The caller owns the value: bind `checked` and flip it in
// `toggled()`, mirroring Toggle/ToggleSwitch. The whole row is the hitbox —
// Windows users click the label, not the 14px square.
Item {
  id: root

  property bool checked: false
  property string label: ""
  property bool hasCursor: false
  property bool focusable: false

  property color foreground: Tokens.text.primary
  property color accent: Tokens.accent.primary

  signal toggled()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.toggled()
  Keys.onSpacePressed: if (focusable) root.toggled()

  readonly property bool hot: mouse.containsMouse || hasCursor
  readonly property int boxSize: Math.max(16, Math.round(Style.font.body * 1.25))

  implicitWidth: box.implicitWidth + (label !== "" ? Style.space(8) + label.implicitWidth : 0)
  implicitHeight: Math.max(boxSize, label !== "" ? label.implicitHeight : 0)

  Row {
    id: box
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    BorderSurface {
      id: square
      width: root.boxSize
      height: root.boxSize
      anchors.verticalCenter: parent.verticalCenter
      radius: Math.max(3, Math.round(Style.cornerRadius * 0.5))
      color: root.checked ? root.accent
        : mouse.pressed ? Util.alpha(root.accent, 0.18)
        : root.hot ? Util.alpha(root.foreground, 0.08)
        : "transparent"
      borderSpec: Border.controlSpec(root.checked ? "selected" : (root.hot || (root.focusable && root.activeFocus) ? "hover-cursor" : "normal"), root.foreground, root.accent)

      Behavior on color { ColorAnimation { duration: Tokens.motion.fast } }

      Text {
        anchors.centerIn: parent
        visible: root.checked
        text: "\u2713"
        color: Tokens.surface.base
        font.family: Style.font.family
        font.pixelSize: root.boxSize * 0.8
        font.bold: true
      }
    }

    Text {
      visible: root.label !== ""
      text: root.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.toggled()
    }
  }
}
