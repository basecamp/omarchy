import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: root

  property string text: ""
  property int tabIndex: -1
  property bool checked: false

  signal clicked()

  Layout.fillWidth: true
  implicitWidth: label.implicitWidth + Style.marginL * 2
  implicitHeight: 26
  radius: Style.radiusXS
  color: area.containsMouse
    ? Color.mHover
    : (checked ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18) : "transparent")
  border.color: checked ? Color.mPrimary : "transparent"
  border.width: checked ? 1 : 0

  Behavior on color { ColorAnimation { duration: Style.animationFast } }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: checked ? Color.mPrimary : Color.mOnSurface
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Style.fontSizeS
    font.bold: checked
    elide: Text.ElideRight
    width: Math.max(0, parent.width - Style.marginM * 2)
    horizontalAlignment: Text.AlignHCenter
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
