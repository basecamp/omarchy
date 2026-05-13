import QtQuick
import qs.Commons
import qs.Services.UI

// Noctalia compat shim. The widget plugins lean on this heavily; it's the
// primary clickable bar element. We mimic Noctalia's surface area
// (icon/text/tooltip/colors/border) but skip the long tail of properties
// no observed plugin actually sets.
Rectangle {
  id: root

  property string icon: ""
  property string text: ""
  property string tooltipText: ""
  property string tooltipDirection: ""
  property real baseSize: Style.baseWidgetSize
  property bool applyUiScale: false
  property real customRadius: -1
  property color colorBg: Style.capsuleColor
  property color colorFg: Color.mOnSurface
  property color colorBgHover: Color.mHover
  property color colorFgHover: Color.mOnHover
  property color colorBorder: Style.capsuleBorderColor
  property color colorBorderHover: Style.capsuleBorderColor
  property bool flat: false

  signal clicked()
  signal rightClicked()
  signal middleClicked()
  signal wheel(int delta)

  readonly property real effectiveSize: Math.round(baseSize * (applyUiScale ? Style.uiScaleRatio : 1))

  implicitWidth: effectiveSize
  implicitHeight: effectiveSize
  radius: customRadius >= 0 ? customRadius : Style.radiusM
  color: mouse.containsMouse ? colorBgHover : colorBg
  border.color: mouse.containsMouse ? colorBorderHover : colorBorder
  border.width: Style.capsuleBorderWidth

  Behavior on color { ColorAnimation { duration: Style.animationFast } }

  Text {
    anchors.centerIn: parent
    text: root.icon ? Icons.get(root.icon) : root.text
    color: mouse.containsMouse ? root.colorFgHover : root.colorFg
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Math.round(Style.fontSizeM * (root.applyUiScale ? Style.uiScaleRatio : 1))
    Behavior on color { ColorAnimation { duration: Style.animationFast } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onEntered: if (root.tooltipText) TooltipService.show(root, root.tooltipText, root.tooltipDirection)
    onExited: TooltipService.hide(root)
    onClicked: function(m) {
      if (m.button === Qt.RightButton) root.rightClicked()
      else if (m.button === Qt.MiddleButton) root.middleClicked()
      else root.clicked()
    }
    onWheel: function(w) { root.wheel(w.angleDelta.y) }
  }
}
