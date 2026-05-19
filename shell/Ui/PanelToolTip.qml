import QtQuick
import QtQuick.Controls
import qs.Commons

// Styled wrapper around Qt Quick Controls ToolTip. Drop-in: declare inside
// the hovered item and bind `visible` to the hover state, e.g.
//   PanelToolTip {
//     visible: mouse.containsMouse
//     text: "Forget network"
//     panelForeground: bar.foreground
//     panelBackground: bar.background
//     fontFamily: bar.fontFamily
//   }
//
// Property names are prefixed `panel*` to avoid clashing with ToolTip's
// built-in `background`/`font` properties.
ToolTip {
  id: root

  property color panelForeground: Color.foreground
  property color panelBackground: Color.background
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall

  delay: 400
  padding: 0

  background: Rectangle {
    color: root.panelBackground
    border.color: Style.normalBorderFor(root.panelForeground, Color.accent)
    border.width: Style.normalBorderWidth
    radius: 0
    opacity: 0.97
  }

  contentItem: Text {
    text: root.text
    color: root.panelForeground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    leftPadding: Style.spacing.controlPaddingX
    rightPadding: Style.spacing.controlPaddingX
    topPadding: Style.spacing.controlPaddingY
    bottomPadding: Style.spacing.controlPaddingY
  }
}
