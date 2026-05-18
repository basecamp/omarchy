import QtQuick
import QtQuick.Controls

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

  property color panelForeground: "#cacccc"
  property color panelBackground: "#101315"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real fontSize: 11

  delay: 400
  padding: 0

  background: Rectangle {
    color: root.panelBackground
    border.color: root.panelForeground
    border.width: 1
    radius: 0
    opacity: 0.97
  }

  contentItem: Text {
    text: root.text
    color: root.panelForeground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    leftPadding: 10
    rightPadding: 10
    topPadding: 6
    bottomPadding: 6
  }
}
