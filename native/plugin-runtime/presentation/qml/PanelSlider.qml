import QtQuick
Item { property var bar: null; property real value: 0; property real from: 0; property real to: 100; signal moved(real value); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; color: "#354052" }; MouseArea { anchors.fill: parent; onPositionChanged: if (pressed) parent.moved(parent.from + mouse.x / width * (parent.to - parent.from)) } }
