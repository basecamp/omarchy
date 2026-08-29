import QtQuick
Item {
  property var bar: null; property real value: 0; property real minimum: 0; property real maximum: 100; property real step: 1; property bool integer: false; property int tickCount: 0
  readonly property bool dragging: mouseArea.pressed
  readonly property real liveValue: value
  signal released(real value)
  signal rightClicked()
  Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; color: "#354052" }
  MouseArea { id: mouseArea; anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onReleased: mouse => { if (mouse.button === Qt.RightButton) parent.rightClicked(); else parent.released(parent.minimum + mouse.x / width * (parent.maximum - parent.minimum)) } }
}
