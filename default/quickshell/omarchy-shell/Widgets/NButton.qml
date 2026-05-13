import QtQuick
import QtQuick.Controls
import qs.Commons

Button {
  id: root
  property string label: ""
  property color colorBg: Color.mSurfaceVariant
  property color colorFg: Color.mOnSurface

  text: label || ""
  background: Rectangle {
    color: root.hovered ? Color.mHover : root.colorBg
    radius: Style.radiusM
    border.color: Color.mOutline
    border.width: Style.borderS
  }
  contentItem: Text {
    text: root.text
    color: root.colorFg
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Style.fontSizeM
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
