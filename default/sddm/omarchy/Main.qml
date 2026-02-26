import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
    id: root
    width: 640
    height: 480
    color: "#000000"

    property string currentUser: userModel.lastUser
    property int sessionIndex: {
        for (var i = 0; i < sessionModel.rowCount(); i++) {
            var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
            if (name.indexOf("uwsm") !== -1)
                return i
        }
        return sessionModel.lastIndex
    }

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
        spacing: root.height * 0.04
        width: parent.width

        Image {
            source: "logo.svg"
            width: root.width * 0.35
            height: Math.round(width * sourceSize.height / sourceSize.width)
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.width * 0.007

            Text {
                text: "\uf023"
                color: "#ffffff"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: root.height * 0.025
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: root.width * 0.17
                height: root.height * 0.04
                color: "#000000"
                border.color: "#ffffff"
                border.width: 1

                TextInput {
                    id: password
                    anchors.fill: parent
                    anchors.margins: root.height * 0.008
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: root.height * 0.02
                    font.letterSpacing: root.height * 0.004
                    passwordCharacter: "\u2022"
                    color: "#ffffff"
                    focus: true

                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(root.currentUser, password.text, root.sessionIndex)
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
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.height * 0.018
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
