import QtQuick

Rectangle {
    id: root

    width: 252
    height: 48
    color: "#52677a"

    Row {
        anchors.fill: parent

        Rectangle {
            width: root.width / 2
            height: root.height
            color: panelMouseArea.pressed ? "#405667" : "transparent"

            Text {
                anchors.centerIn: parent
                text: "Panel"
                color: "white"
            }

            MouseArea {
                id: panelMouseArea
                objectName: "panelToggle"
                anchors.fill: parent
                onClicked: runtime.requestSurfaceIntent("panel", "toggle")
            }
        }

        Rectangle {
            width: root.width / 2
            height: root.height
            color: overlayMouseArea.pressed ? "#405667" : "transparent"

            Text {
                anchors.centerIn: parent
                text: "Overlay"
                color: "white"
            }

            TapHandler {
                id: overlayMouseArea
                objectName: "overlayToggle"
                onTapped: runtime.requestSurfaceIntent("overlay", "toggle")
            }
        }
    }
}
