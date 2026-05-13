import QtQuick
import qs.Commons

// Noctalia compat shim. Renders an icon by name through the Icons map.
Text {
  id: root
  property string icon: ""
  property real pointSize: 14
  property bool applyUiScale: true

  text: Icons.get(icon)
  color: Color.mOnSurface
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: Math.round(pointSize * (applyUiScale ? Style.uiScaleRatio : 1))
  verticalAlignment: Text.AlignVCenter
  horizontalAlignment: Text.AlignHCenter
  renderType: Text.NativeRendering
}
