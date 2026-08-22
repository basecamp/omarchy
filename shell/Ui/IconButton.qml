import QtQuick
import QtQuick.Controls
import qs.Commons

// Icon-only button for toolbars, caption bars, and tray-adjacent chrome.
// Square hitbox with a generous target area even when the glyph is small —
// caption buttons and titlebar controls depend on this (Rule 2: everything
// possible with the mouse).
//
// `danger` flips hover/press to the semantic danger color for destructive
// actions (window close). States follow the shared kit priority: pressed >
// focus > hover > idle.
BorderSurface {
  id: root

  property string iconText: ""
  property string tooltipText: ""

  property bool danger: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false
  property bool selected: false

  // Square by default; consumers can stretch via explicit width/height.
  property int size: Math.max(28, Math.round(Style.spacing.controlHeight * 0.9))
  property real glyphSize: Style.font.icon

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitWidth: size
  implicitHeight: size
  radius: Style.cornerRadius

  readonly property bool hot: mouse.containsMouse || hasCursor
  readonly property color _stateColor: danger ? Tokens.state.danger : Tokens.accent.primary
  readonly property color _fg: Tokens.text.primary

  color: mouse.pressed ? Util.alpha(_stateColor, 0.28)
    : (focusable && activeFocus) ? Util.alpha(_stateColor, 0.20)
    : hot ? Util.alpha(_stateColor, 0.14)
    : selected ? Util.alpha(_stateColor, 0.18)
    : "transparent"

  borderSpec: bordered || hot || (focusable && activeFocus)
    ? Border.controlSpec(hot || (focusable && activeFocus) ? "hover-cursor" : "normal", _fg, _stateColor)
    : Border.none()

  Behavior on color { ColorAnimation { duration: Tokens.motion.fast } }

  ToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    delay: 400
    padding: 0
    background: BorderSurface {
      color: Tokens.surface.overlay
      radius: Style.cornerRadius
    }
    contentItem: Text {
      text: root.tooltipText
      color: Tokens.text.primary
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    anchors.centerIn: parent
    text: root.iconText
    color: root._fg
    font.family: Style.font.family
    font.pixelSize: root.glyphSize
    anchors.verticalCenterOffset: -1
  }

  MouseArea {
    id: mouse
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
