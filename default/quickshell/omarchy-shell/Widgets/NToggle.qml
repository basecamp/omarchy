import QtQuick
import QtQuick.Controls
import qs.Commons

Switch {
  id: root
  property string label: ""

  indicator: Rectangle {
    implicitWidth: 32
    implicitHeight: 18
    x: root.leftPadding
    y: root.height / 2 - height / 2
    radius: height / 2
    color: root.checked ? Color.mPrimary : Color.mSurfaceVariant
    border.color: Color.mOutline
    border.width: Style.borderS

    Rectangle {
      x: root.checked ? parent.width - width - 2 : 2
      y: 2
      width: parent.height - 4
      height: parent.height - 4
      radius: height / 2
      color: Color.mOnSurface
      Behavior on x { NumberAnimation { duration: Style.animationFast } }
    }
  }

  contentItem: Text {
    leftPadding: 38
    text: root.label || root.text
    color: Color.mOnSurface
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Style.fontSizeS
    verticalAlignment: Text.AlignVCenter
  }
}
