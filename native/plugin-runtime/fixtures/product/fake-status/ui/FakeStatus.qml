import QtQuick
import QtQml

Item {
    id: root
    width: 420
    height: 520

    readonly property string surfaceRole: "panel"
    property var statuses: []
    property bool undeclaredOpenDenied: false

    function refreshForTest() {
        statuses = runtime.invoke("fake_status_list", {resource: 1})
    }

    function acknowledgeForTest(id) {
        return runtime.invoke("fake_status_acknowledge", {resource: 1, id: id})
    }

    function openForTest(url) {
        const accepted = runtime.invoke("open_uri", {url: url})
        undeclaredOpenDenied = !accepted
        return accepted
    }

    Component.onCompleted: refreshForTest()

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: "#10151d"
        border.color: "#293445"

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            Text {
                text: "STATUS STREAM"
                color: "#8fa8c7"
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.6
            }

            Text {
                text: root.statuses.length + " updates"
                color: "#f4f7fb"
                font.pixelSize: 28
                font.bold: true
            }

            Repeater {
                model: root.statuses

                Rectangle {
                    required property var modelData
                    width: 372
                    height: 78
                    radius: 12
                    color: modelData.unread ? "#1d2a3a" : "#171d26"
                    border.color: modelData.unread ? "#4d86bd" : "#29313d"

                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        spacing: 5

                        Text {
                            text: modelData.project.toUpperCase()
                            color: "#77b8ed"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        Text {
                            text: modelData.title
                            color: "#eef4fb"
                            font.pixelSize: 15
                        }
                    }
                }
            }
        }
    }
}
