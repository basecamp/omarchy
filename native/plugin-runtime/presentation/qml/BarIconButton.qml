import QtQuick
Item {
  property var bar: null
  property Component iconComponent
  signal pressed(int buttonCode)
  Loader { anchors.fill: parent; sourceComponent: iconComponent }
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onPressed: parent.pressed(mouse.button) }
}
