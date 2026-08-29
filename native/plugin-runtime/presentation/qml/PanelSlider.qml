import QtQuick
Item {
  property var bar: null; property real value: 0; property real minimum: 0; property real maximum: 100; property real step: 1; property bool integer: false; property int tickCount: 0
  signal released(real value)
  Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; color: "#354052" }
  MouseArea { anchors.fill: parent; onReleased: parent.released(parent.minimum + mouse.x / width * (parent.maximum - parent.minimum)) }
}
