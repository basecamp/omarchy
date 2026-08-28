import QtQuick

Rectangle {
    id: root
    color: mouse.pressed ? "#ff3377" : "#3366ff"

    Rectangle {
        width: 12
        height: 12
        radius: 6
        color: "white"

        SequentialAnimation on x {
            loops: Animation.Infinite

            NumberAnimation {
                from: 0
                to: 52
                duration: 250
            }

            NumberAnimation {
                from: 52
                to: 0
                duration: 250
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
    }
}
