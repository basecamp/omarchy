import QtQuick
import QtQml

Item {
    id: root
    width: 252
    height: 48

    readonly property string surfaceRole: "bar-embedded"
    property int secondsRemaining: 25 * 60
    property int completedSessions: 0
    property bool active: false
    property real pulse: 0.0

    function toggleForTest() {
        active = !active
    }

    function completeForTest() {
        active = false
        secondsRemaining = 25 * 60
        completedSessions += 1
        runtime.invoke("storage_write", {
            key: "timer-state",
            value: JSON.stringify({completedSessions: completedSessions})
        })
        runtime.invoke("notification_send", {
            category: "timer",
            title: "Focus interval complete",
            body: "Time for a break"
        })
        runtime.invoke("audio_play_cue", {cue: "timer-complete"})
    }

    Component.onCompleted: runtime.invoke("storage_read", {key: "timer-state"})

    Rectangle {
        anchors.fill: parent
        radius: 15
        color: "#15151d"
        border.color: "#3d3b52"

        Rectangle {
            id: progress
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, root.secondsRemaining / (25 * 60)))
            radius: parent.radius
            color: Qt.rgba(0.50, 0.36, 0.94, 0.24 + root.pulse * 0.12)
        }

        Row {
            anchors.centerIn: parent
            spacing: 12

            Text {
                text: root.active ? "FOCUS" : "READY"
                color: "#bba8ff"
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.2
            }

            Text {
                text: Math.floor(root.secondsRemaining / 60).toString().padStart(2, "0") + ":" + (root.secondsRemaining % 60).toString().padStart(2, "0")
                color: "#f6f1ff"
                font.pixelSize: 19
                font.family: "monospace"
                font.bold: true
            }

            Text {
                text: "●".repeat(Math.min(root.completedSessions, 4))
                color: "#78dba9"
                font.pixelSize: 10
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.active = !root.active
        }
    }

    SequentialAnimation on pulse {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
    }
}
