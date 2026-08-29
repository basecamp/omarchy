import QtQuick
import QtQml

Item {
    id: root
    width: 520
    height: 260

    readonly property string surfaceRole: "panel"
    readonly property bool acceptsKeyboardFocus: false
    readonly property int maximumFramesPerSecond: 15
    property int observedChanges: 0
    property string permissionState: "WAITING"

    function refreshPermission() {
        observedChanges += 1
        permissionState = runtime.permissionState("notifications.send", "send").toUpperCase()
    }

    Component.onCompleted: {
        permissionState = runtime.permissionState("notifications.send", "send").toUpperCase()
    }

    Connections {
        target: runtime
        function onPermissionsChanged() { root.refreshPermission() }
    }

    Rectangle {
        anchors.fill: parent
        color: "#11131b"
        border.color: root.permissionState === "GRANTED" ? "#65d7a1" : "#f0b35b"
        border.width: 3
        radius: 18

        Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 18

            Text {
                width: parent.width
                text: "PERMISSION SNAPSHOT"
                color: "#9ca7c2"
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 2
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.permissionState
                color: root.permissionState === "GRANTED" ? "#65d7a1" : "#f0b35b"
                font.pixelSize: 34
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: "permissionsChanged observations: " + root.observedChanges
                color: "#d3d8e5"
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
