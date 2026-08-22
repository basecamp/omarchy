import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: cell
  property string label: ""
  signal picked()
  radius: Tokens.radius.medium
  color: cellMouse.containsMouse ? Util.alpha(Tokens.accent.primary, 0.28) : Tokens.surface.raised
  border.color: cellMouse.containsMouse ? Tokens.accent.primary : Tokens.border.subtle
  border.width: 1
  Text {
    anchors.centerIn: parent
    text: cell.label
    color: Tokens.text.primary
    font.pixelSize: Style.font.bodySmall
    font.family: "sans-serif"
  }
  MouseArea {
    id: cellMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: cell.picked()
  }
}
