import QtQuick
import QtQuick.Controls
import qs.Commons

// Styled wrapper around Qt Quick Controls ToolTip. Drop-in: declare inside
// the hovered item and bind `visible` to the hover state, e.g.
//   PanelToolTip {
//     visible: mouse.containsMouse
//     text: "Forget network"
//   }
//
// Defaults pull from [tooltip] in shell.toml via Color.tooltip.*. Override
// the panel* properties per-instance only when you need a tooltip that
// intentionally diverges from the theme.
//
// Property names are prefixed `panel*` to avoid clashing with ToolTip's
// built-in `background`/`font` properties.
ToolTip {
  id: root

  property color panelForeground: Color.tooltip.text
  property color panelBackground: Color.tooltip.background
  property color panelBorder: Color.tooltip.border
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall

  readonly property var panelBorderSpec: Border.localOrSurfaceSpec("tooltip", "border", panelBorder, Color.tooltip.border, Style.normalBorderWidth)

  delay: 400
  padding: 0

  background: BorderSurface {
    color: root.panelBackground
    borderSpec: root.panelBorderSpec
    radius: Style.cornerRadius
  }

  contentItem: Text {
    text: root.text
    color: root.panelForeground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    leftPadding: Border.left(root.panelBorderSpec) + Style.spacing.controlPaddingX
    rightPadding: Border.right(root.panelBorderSpec) + Style.spacing.controlPaddingX
    topPadding: Border.top(root.panelBorderSpec) + Style.spacing.controlPaddingY
    bottomPadding: Border.bottom(root.panelBorderSpec) + Style.spacing.controlPaddingY
  }
}
