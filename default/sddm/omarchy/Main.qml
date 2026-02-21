import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
    id: root
    width: 640
    height: 480
    color: "#000000"

    property string currentUser: userModel.lastUser

    Connections {
        target: sddm
        function onLoginFailed() {
            errorMessage.text = "Login failed"
            password.text = ""
            password.focus = true
        }
        function onLoginSucceeded() {
            errorMessage.text = ""
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 30
        width: parent.width

        Image {
            source: "logo.svg"
            width: 500
            height: Math.round(width * sourceSize.height / sourceSize.width)
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Text {
                text: "\uf023"
                color: "#ffffff"
                font.family: "JetBrainsMono NF"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: 250
                height: 32
                color: "#000000"
                border.color: "#ffffff"
                border.width: 1

                TextInput {
                    id: password
                    anchors.fill: parent
                    anchors.margins: 6
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    font.family: "JetBrainsMono NF"
                    font.pixelSize: 14
                    font.letterSpacing: 3
                    passwordCharacter: "\u2022"
                    color: "#ffffff"
                    focus: true

                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(root.currentUser, password.text, sessionModel.lastIndex)
                            event.accepted = true
                        }
                    }
                }
            }
        }

        Text {
            id: errorMessage
            text: ""
            color: "#f7768e"
            font.family: "JetBrainsMono NF"
            font.pixelSize: 12
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
