import QtQuick
import qs.Commons

// A single button in a mutually-exclusive choice group (a Row of these
// makes a "segmented control"). Distinct from PillButton because it has
// a real `selected` state semantic — used for picking between options
// (bar position: top/bottom/left/right), not for momentary actions.
//
// Selected styling uses the accent fill+border; focus styling uses the
// Style.focusBorderColor outline so keyboard nav can land on a non-selected
// option without it reading as the chosen one. This separation matters in
// the settings panel and any future "pick one" UI.
Rectangle {
  id: root

  property string text: ""
  property bool selected: false

  // Panel-cursor flag. Same role as PillButton.hasCursor: panels that own
  // their own cursor state bind this to drive the keyboard highlight
  // separately from real activeFocus. Visuals match the activeFocus look
  // (foreground 2px border) so cursor and Tab focus read the same.
  property bool hasCursor: false

  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property string fontFamily: "monospace"
  property real fontSize: 12

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: true
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  implicitWidth: Math.max(56, label.implicitWidth + 22)
  implicitHeight: 28
  radius: Style.cornerRadius

  color: selected
    ? Qt.rgba(accent.r, accent.g, accent.b, 0.18)
    : (mouse.containsMouse ? Style.hotFill : background)
  border.color: selected
    ? accent
    : (activeFocus || hasCursor ? foreground : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.4))
  border.width: selected ? 2 : (activeFocus || hasCursor ? 2 : 1)

  Behavior on color { ColorAnimation { duration: 100 } }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.selected ? root.accent : root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.selected
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.forceActiveFocus()
      root.clicked()
    }
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
