import QtQuick
import QtQml

Item {
    id: root
    width: 520
    height: 260

    readonly property string surfaceRole: "panel"
    readonly property bool acceptsKeyboardFocus: false
    readonly property int maximumFramesPerSecond: 15
    property var deniedCall: null
    property string phase: "ATTEMPTING"
    property string detail: "Invoking unrequested notifications.send/send"

    function finishAttempt() {
        if (deniedCall.ok) {
            phase = "ESCAPED"
            detail = "SECURITY FAILURE: unrequested effect was allowed"
        } else {
            phase = "DENIED"
            detail = "Broker rejected unrequested operation: " + deniedCall.error
        }
    }

    function beginAttempt() {
        deniedCall = runtime.invoke("notification_send", {
            category: "spoofed",
            title: "This must not appear",
            body: "The manifest never requested notification authority"
        })
        if (deniedCall && deniedCall.finished)
            finishAttempt()
    }

    Timer {
        interval: 1
        running: true
        repeat: false
        onTriggered: root.beginAttempt()
    }

    Connections {
        target: root.deniedCall
        function onFinishedChanged() {
            if (root.deniedCall.finished)
                root.finishAttempt()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#191113"
        border.color: root.phase === "DENIED" ? "#ff7676" : "#8a5960"
        border.width: 3
        radius: 18

        Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 18

            Text {
                width: parent.width
                text: "AUTHORITATIVE DENIAL PROOF"
                color: "#c99ca4"
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 2
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.phase
                color: root.phase === "DENIED" ? "#ff7676" : "#fff1f2"
                font.pixelSize: 34
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.detail
                color: "#e0c7ca"
                font.pixelSize: 15
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
