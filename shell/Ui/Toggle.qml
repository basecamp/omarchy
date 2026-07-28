import QtQuick
import qs.Commons

// Labeled toggle row: title + optional description on the left, a
// `ToggleSwitch` on the right. Clicking anywhere on the row emits `clicked()`;
// consumers flip `checked` in response (the component is stateless about the
// actual value so it composes cleanly with model-driven UI).
//
// Cursor and focus styling match the rest of the kit: hasCursor / mouse
// hover and activeFocus share the hover-cursor defaults.
//
// `rounded` is forwarded to the switch, which auto-detects from
// Style.cornerRadius: pill shape when Hyprland corners are rounded, square on
// sharp. Callers can override per-instance.
BorderSurface {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false

  // Panel-cursor flag. Same role as Button.hasCursor:
  // panels with their own keyboard cursor bind this to drive the highlight
  // separately from activeFocus. Visuals use the same hover-cursor tokens.
  property bool hasCursor: false

  // Switch shape follows the theme by default: pill on round, square on sharp.
  // Override per-instance if a caller wants the opposite.
  property bool rounded: Style.cornerRadius > 0

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real titleSize: Style.font.subtitle
  property real descriptionSize: Style.font.caption

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: true
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  implicitHeight: Math.max(54, content.implicitHeight + Style.spacing.huge)
  implicitWidth: Style.space(240)
  radius: Style.cornerRadius

  readonly property bool _hot: hasCursor || mouse.containsMouse
  readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (_hot ? "hover-cursor" : "normal"), foreground, accent)

  color: Style.controlFill(activeFocus, _hot, foreground, accent)
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 100 } }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.borderLeft + Style.spacing.rowPaddingX
    anchors.rightMargin: root.borderRight + Style.spacing.rowPaddingX
    spacing: Style.spacing.rowPaddingX

    Column {
      width: parent.width - track.width - parent.spacing
      spacing: Style.spacing.xs
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

    // The row owns the click, so the switch is presentation only here.
    ToggleSwitch {
      id: track
      checked: root.checked
      rounded: root.rounded
      foreground: root.foreground
      accent: root.accent
      interactive: false
      anchors.verticalCenter: parent.verticalCenter
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
