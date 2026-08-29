import QtQuick

Rectangle {
    id: root
    property int timerTicks: 0
    color: mouse.pressed ? "#80ff3377" : "#803366ff"

    Timer {
        interval: 25
        running: true
        repeat: true
        onTriggered: root.timerTicks += 1
    }

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
