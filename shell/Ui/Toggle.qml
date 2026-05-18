import QtQuick
import qs.Commons

// Labeled toggle row: title + optional description on the left, a switch
// on the right. Clicking anywhere on the row emits `clicked()`; consumers
// flip `checked` in response (the component is stateless about the actual
// value so it composes cleanly with model-driven UI).
//
// Focus styling follows the shared Style tokens (accent border + tinted
// fill on activeFocus) so keyboard nav looks the same here as on
// ChoiceButton and other focusable Ui components.
//
// `rounded` auto-detects from Style.cornerRadius so the switch follows
// the theme: pill shape on round-corners themes, square on sharp.
// Callers can override per-instance.
Rectangle {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false

  // Panel-cursor flag. Same role as PillButton.hasCursor / ChoiceButton.hasCursor:
  // panels with their own keyboard cursor bind this to drive the highlight
  // separately from activeFocus. Visuals match the activeFocus look (accent
  // border + tinted fill via Style tokens) so cursor and Tab focus read the same.
  property bool hasCursor: false

  // Switch shape follows the theme by default: pill on round, square on sharp.
  // Override per-instance if a caller wants the opposite.
  property bool rounded: Style.cornerRadius > 0

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: "monospace"
  property real titleSize: 13
  property real descriptionSize: 10

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: true
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  implicitHeight: Math.max(54, content.implicitHeight + 18)
  implicitWidth: 240
  radius: Style.cornerRadius

  color: activeFocus
    ? Style.focusFillColor
    : ((hasCursor || mouse.containsMouse) ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08) : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.03))
  border.color: activeFocus
    ? Style.focusBorderColor
    : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  border.width: activeFocus ? Style.focusBorderWidth : 1

  Behavior on color { ColorAnimation { duration: 100 } }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    spacing: 12

    Column {
      width: parent.width - track.width - parent.spacing
      spacing: 3
      anchors.verticalCenter: parent.verticalCenter

      Text {
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.titleSize
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        visible: root.description !== ""
        text: root.description
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: root.descriptionSize
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }

    Rectangle {
      id: track
      width: 42
      height: 22
      radius: root.rounded ? height / 2 : 0
      color: root.checked
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      border.color: root.checked
        ? root.accent
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
      border.width: 1
      anchors.verticalCenter: parent.verticalCenter

      Behavior on color { ColorAnimation { duration: 120 } }

      Rectangle {
        width: 16
        height: 16
        radius: root.rounded ? 8 : 0
        x: root.checked ? track.width - width - 3 : 3
        y: 3
        color: root.checked ? root.accent : Qt.darker(root.foreground, 1.25)

        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
