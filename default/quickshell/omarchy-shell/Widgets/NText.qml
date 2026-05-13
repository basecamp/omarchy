import QtQuick
import qs.Commons

// Noctalia compat shim. The original supports pointSize (interpreted as
// pixel size in Noctalia) plus an applyUiScale flag. We translate to
// font.pixelSize directly; uiScaleRatio comes from Style.
Text {
  id: root
  property real pointSize: 12
  property bool applyUiScale: true
  property var customFont: null

  color: Color.mOnSurface
  font.family: customFont || "JetBrainsMono Nerd Font"
  font.pixelSize: Math.round(pointSize * (applyUiScale ? Style.uiScaleRatio : 1))
  font.weight: Style.fontWeightRegular
  verticalAlignment: Text.AlignVCenter
  renderType: Text.NativeRendering
}
