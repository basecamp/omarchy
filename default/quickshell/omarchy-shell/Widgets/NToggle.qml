import QtQuick
import qs.Commons

Rectangle {
  id: root

  property string label: ""
  property string text: ""
  property bool checked: false

  signal toggled(var value)
  signal clicked()

  implicitWidth: labelItem.visible ? indicator.width + 8 + labelItem.implicitWidth : indicator.width
  implicitHeight: Math.max(indicator.height, labelItem.implicitHeight)
  color: "transparent"
  opacity: enabled ? 1 : 0.4

  Rectangle {
    id: indicator
    width: 32
    height: 18
    anchors.verticalCenter: parent.verticalCenter
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

  Text {
    id: labelItem
    visible: (root.label || root.text) !== ""
    anchors.left: indicator.right
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    text: root.label || root.text
    color: Color.mOnSurface
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Style.fontSizeS
    verticalAlignment: Text.AlignVCenter
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.checked = !root.checked
      root.clicked()
      root.toggled(root.checked)
    }
  }
}
