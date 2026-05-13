import QtQuick
import QtQuick.Controls
import qs.Commons

ComboBox {
  id: root
  property string label: ""

  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: Style.fontSizeS
  background: Rectangle {
    color: Color.mSurfaceVariant
    border.color: Color.mOutline
    border.width: Style.borderS
    radius: Style.radiusS
  }
}
