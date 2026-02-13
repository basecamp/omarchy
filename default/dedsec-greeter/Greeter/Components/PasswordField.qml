pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../Common"

// Custom password field using TextInput (avoids blackholed QtQuick.Controls)
FocusScope {
    id: passwordField

    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias passwordCharacter: input.passwordCharacter
    property alias font: input.font
    property alias color: input.color
    property alias rem: cursorMetrics.width

    property bool enabled: true

    signal accepted()
    signal textEdited()

    function forceActiveFocus() {
        input.forceActiveFocus();
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: "transparent"
        border {
            color: Theme.dedsecGray
            width: 2
        }
    }

    TextInput {
        id: input

        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: cursorMetrics.width + 6
            topMargin: 4
            bottomMargin: 4
        }

        verticalAlignment: TextInput.AlignVCenter
        clip: true

        font {
            pixelSize: 16
            letterSpacing: 5
        }

        echoMode: TextInput.Password
        passwordCharacter: "█"

        enabled: passwordField.enabled
        focus: true
        activeFocusOnTab: true

        onAccepted: passwordField.accepted()
        onTextEdited: passwordField.textEdited()

        TextMetrics {
            id: cursorMetrics
            font: input.font
            text: "▁"
        }

        cursorDelegate: Text {
            id: cursor

            color: input.color
            font: input.font
            text: "▁"

            Timer {
                id: blinkDelayTimer
                interval: 500
                onTriggered: {
                    blinkAnimation.running = true;
                }
            }

            Connections {
                target: passwordField

                function onEnabledChanged() {
                    if (passwordField.enabled) {
                        blinkDelayTimer.running = true;
                    } else {
                        blinkDelayTimer.running = false;
                        blinkAnimation.running = false;
                        cursor.opacity = 0;
                    }
                }
            }

            Connections {
                target: input

                function onTextEdited() {
                    blinkDelayTimer.restart();
                    blinkAnimation.running = false;
                    cursor.opacity = 1;
                }
            }

            SequentialAnimation on opacity {
                id: blinkAnimation

                loops: Animation.Infinite

                NumberAnimation {
                    from: 1
                    to: 1
                    duration: 500
                }

                NumberAnimation {
                    from: 1
                    to: 0
                    duration: 300
                }

                NumberAnimation {
                    from: 0
                    to: 0
                    duration: 300
                }
            }
        }
    }

    Component.onDestruction: {
        input.focus = false;
    }
}
