import QtQuick
import QtQuick.Controls
import qs.Commons

CheckBox {
  id: root
  property string label: ""
  text: label || ""
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: Style.fontSizeS
}
