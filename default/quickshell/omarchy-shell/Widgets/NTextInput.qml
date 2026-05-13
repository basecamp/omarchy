import QtQuick
import QtQuick.Controls
import qs.Commons

TextField {
  id: root
  property string label: ""
  property string description: ""
  property string defaultValue: ""

  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: Style.fontSizeS
  color: Color.mOnSurface
  background: Rectangle {
    color: Color.mSurfaceVariant
    border.color: root.focus ? Color.mPrimary : Color.mOutline
    border.width: Style.borderS
    radius: Style.radiusS
  }
}
