import QtQuick
import QtQuick.Controls
import qs.Commons

// The button. One component for every clickable thing in the kit.
// States compose independently and are applied in priority order:
//
//   pressed (mouse down)         pressed fill
//   activeFocus (Tab focus)      accent ring + accent fill
//   selected                     accent fill + accent border
//   active                       foreground tint fill (highlighted)
//   hasCursor || hover           hot fill
//   idle                         transparent or 1px border if `bordered`
//
// All fills/borders come from `qs.Commons.Style` tokens, so themes
// control the look via [style] in shell.toml.
//
// Emits `hovered(bool)` so panels with their own keyboard cursor model
// can update state on mouse enter/leave.
Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""

  // State flags (see comment above for paint priority).
  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false

  // Colors. Defaults track the theme; per-instance overrides are honored.
  property color foreground: Color.foreground
  property color background: "transparent"
  property color accent: Color.accent

  // Sizing.
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real iconRotation: 0
  property real horizontalPadding: 10
  property real verticalPadding: 6
  property bool leftAlign: false

  // Tooltip palette. Auto-rendered if tooltipText is set.
  property color tooltipBackground: Color.background
  property color tooltipForeground: foreground

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitWidth: row.implicitWidth + horizontalPadding * 2
  implicitHeight: row.implicitHeight + verticalPadding * 2
  radius: Style.cornerRadius

  readonly property bool hot: mouseArea.containsMouse || hasCursor
  readonly property bool _showFocusRing: focusable && activeFocus

  color: mouseArea.pressed ? Style.pressedFill
    : _showFocusRing       ? Style.focusFillColor
    : selected             ? Style.selectedAccentFill
    : hot                  ? Style.hotFill
    : active               ? Style.selectedFill
    : background

  // Border color follows the same precedence as fill: focus ring wins,
  // then selected, then cursor on bordered (paints accent so the chip
  // structure clearly reads as "cursor is here"), then plain bordered
  // (foreground), then nothing.
  border.color: _showFocusRing ? Style.focusBorderColor
    : selected                 ? accent
    : (bordered && hot)        ? Style.focusBorderColor
    : bordered                 ? foreground
    : Style.idleBorderColor

  // selected+hot thickens to the focus-ring width so the cursor remains
  // visible on the chosen option (otherwise selected's accent fill+border
  // masks any hot fill). bordered+hot also thickens so the chip cursor
  // reads as a deliberate state change rather than a faint tint.
  border.width: _showFocusRing ? Style.focusBorderWidth
    : selected                 ? (hot ? Style.focusBorderWidth : Math.max(Style.borderWidth, 2))
    : (bordered && hot)        ? Style.focusBorderWidth
    : bordered                 ? Style.borderWidth
    : 0

  Behavior on color { ColorAnimation { duration: 120 } }

  ToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    delay: 400
    padding: 0
    background: Rectangle {
      color: root.tooltipBackground
      border.color: root.tooltipForeground
      border.width: 1
      radius: 0
      opacity: 0.97
    }
    contentItem: Text {
      text: root.tooltipText
      color: root.tooltipForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      leftPadding: 10
      rightPadding: 10
      topPadding: 6
      bottomPadding: 6
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? root.horizontalPadding : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: 8

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      color: root.selected ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      rotation: root.iconRotation
      transformOrigin: Item.Center
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.text !== ""
      text: root.text
      color: root.selected ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (root.focusable) root.forceActiveFocus()
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
