import QtQuick

Item {
    id: root
    width: 520
    height: 260

    readonly property string surfaceRole: "panel"
    readonly property bool acceptsKeyboardFocus: false
    readonly property int maximumFramesPerSecond: 15
    property bool pointerProof: false
    property var inputRegions: [{x: 0, y: 0, width: 520, height: 260}]
    property string permissionState: {
        const capability = runtime.permissions["notifications.send"]
        const operations = capability && capability["operations"]
        return operations && operations["send"] === "granted" ? "GRANTED" : "DENIED"
    }

    Rectangle {
        anchors.fill: parent
        color: "#11131b"
        border.color: root.permissionState === "GRANTED" ? "#65d7a1" : "#f0b35b"
        border.width: 3
        radius: 18
        MouseArea {
            anchors.fill: parent
            onClicked: root.pointerProof = true
        }

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
                text: root.pointerProof ? "POINTER ROUTED" : "POINTER WAITING"
                color: root.pointerProof ? "#65d7a1" : "#9ca7c2"
                font.pixelSize: 13
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
                text: "immutable for this plugin generation"
                color: "#d3d8e5"
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
