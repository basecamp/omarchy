import QtQuick
import QtQuick.Controls
import qs.Commons

// The button. One component for every clickable thing in the kit.
// States compose independently and are applied in priority order:
//
//   pressed (mouse down)         pressed fill
//   activeFocus (Tab focus)      focus fill + focus border token
//   hasCursor || hover           hover-cursor fill (+ border if `bordered`)
//   selected                     selected fill + optional selected border
//   active                       selected fill
//   idle                         transparent or normal border if `bordered`
//
// All fills/borders come from `qs.Commons.Style` tokens, so themes
// control the look via [controls] in shell.toml.
//
// Emits `hovered(bool)` so panels with their own keyboard cursor model
// can update state on mouse enter/leave.
BorderSurface {
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
  property bool iconSpinning: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property bool leftAlign: false

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  // Tooltip palette. Auto-rendered if tooltipText is set. Defaults pull
  // from [tooltip] in shell.toml; override per-instance only when a button
  // intentionally wants a tooltip that diverges from the theme.
  property color tooltipBackground: Color.tooltip.background
  property color tooltipForeground: Color.tooltip.text
  property color tooltipBorder: Color.tooltip.border

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitWidth: row.implicitWidth + horizontalPadding * 2 + borderLeft + borderRight
  implicitHeight: row.implicitHeight + verticalPadding * 2 + borderTop + borderBottom
  radius: Style.cornerRadius

  readonly property bool hot: mouseArea.containsMouse || hasCursor
  readonly property bool _showFocusRing: focusable && activeFocus
  readonly property color _selectedColor: Style.selectedStateColor(root.foreground, root.accent)
  readonly property var _tooltipBorderSpec: Border.localOrSurfaceSpec("tooltip", "border", root.tooltipBorder, Color.tooltip.border, Math.max(1, Style.normalBorderWidth))
  readonly property var _selectedBorderSpec: Border.controlSpec("selected", root.foreground, root.accent)
  readonly property var _normalBorderSpec: Border.controlSpec("normal", root.foreground, root.accent)
  readonly property var _borderSpec: _showFocusRing ? Border.controlSpec("focus", root.foreground, root.accent)
    : hot                      ? Border.controlSpec("hover-cursor", root.foreground, root.accent)
    : selected                 ? (Border.controlHasWidth("selected") ? _selectedBorderSpec : (bordered ? _normalBorderSpec : Border.none()))
    : bordered                 ? _normalBorderSpec
    : Border.none()

  color: mouseArea.pressed ? Style.pressedFillFor(root.foreground, root.accent)
    : _showFocusRing       ? Style.focusFillFor(root.foreground, root.accent)
    : hot                  ? Style.hoverFillFor(root.foreground, root.accent)
    : selected             ? Style.selectedFillFor(root.foreground, root.accent)
    : active               ? Style.selectedFillFor(root.foreground, root.accent)
    : background

  // Border follows the same state precedence as fill. Buttons stay
  // borderless at rest unless `bordered` is set, but hover-cursor/focus
  // always use the shared cursor border so the keyboard target is visible
  // and consistent with the rest of the kit. Selected borders are off by
  // default for plain buttons; explicitly bordered buttons keep their
  // normal border when selected unless selected-border-width opts in to a
  // dedicated selected border.
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 120 } }

  ToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    delay: 400
    padding: 0
    background: BorderSurface {
      color: root.tooltipBackground
      borderSpec: root._tooltipBorderSpec
      radius: 0
    }
    contentItem: Text {
      text: root.tooltipText
      color: root.tooltipForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      leftPadding: Border.left(root._tooltipBorderSpec) + Style.spacing.controlPaddingX
      rightPadding: Border.right(root._tooltipBorderSpec) + Style.spacing.controlPaddingX
      topPadding: Border.top(root._tooltipBorderSpec) + Style.spacing.controlPaddingY
      bottomPadding: Border.bottom(root._tooltipBorderSpec) + Style.spacing.controlPaddingY
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? root.contentLeftInset : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: Style.spacing.controlGap

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      rotation: root.iconSpinning ? 0 : root.iconRotation
      transformOrigin: Item.Center
      anchors.verticalCenter: parent.verticalCenter

      RotationAnimation on rotation {
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: root.iconSpinning
      }
    }

    Text {
      visible: root.text !== ""
      text: root.text
      color: root.selected ? root._selectedColor : root.foreground
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
