import QtQuick
import QtQuick.Layouts

import "../Common"
import "../Config"

Item {
    id: root

    component InfoField: Column {
        id: field
        property string label: "FIELD"
        property string value: "VALUE"
        property alias fieldValueOpacity: fieldValue.opacity

        Text {
            id: fieldLabel
            text: field.label
            color: Theme.textPrimaryDim
            font {
                family: Settings.fontFamily
                pixelSize: 14
            }
        }

        Text {
            id: fieldValue
            text: field.value
            color: Theme.textPrimary
            font {
                family: Settings.fontFamily
                pixelSize: 22
                weight: 500
            }
        }
    }

    ColumnLayout {
        width: parent.width * 0.55
        height: parent.height

        spacing: 15

        RowLayout {
            id: row
            spacing: 10

            InfoField {
                id: employeeId
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                label: "OPERATOR ID"
                value: Settings.identity.id
            }
            InfoField {
                id: employeeClass
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                label: "ACCESS"
                value: Settings.identity.class
            }
        }

        InfoField {
            id: employeeName
            Layout.fillWidth: true
            label: "FULL NAME"
            value: Settings.identity.fullName
        }

        Item {

            Layout.fillHeight: true
        }

        Image {
            Layout.bottomMargin: 2  // optical compensation
            fillMode: Image.PreserveAspectFit
            source: "../Resources/id-barcode.svg"
            width: parent.width
        }
    }

    Item {
        id: profilePicture
        // width: parent.width * 0.40
        width: parent.height / 5 * 4
        height: parent.height

        anchors {
            right: parent.right
        }

        Rectangle {
            anchors.fill: parent
            color: '#1effffff'
        }

        Image {
            source: "../Resources/user.svg"
            opacity: 0.9
        }
    }

    SequentialAnimation {
        id: revealAnimation
        running: true

        // SECTION Setup

        PropertyAction {
            target: root
            property: "opacity"
            value: 0
        }
        PropertyAction {
            targets: [employeeId, employeeClass, employeeName]
            property: "fieldValueOpacity"
            value: 0
        }

        ScriptAction {
            script: revealAnimation.pause()
        }

        // SECTION Begin

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1
                duration: 150
            }
            NumberAnimation {
                target: employeeId
                property: "fieldValueOpacity"
                to: 1
                duration: 150
            }
            ParallelAnimation {

                NumberAnimation {
                    target: employeeClass
                    property: "fieldValueOpacity"
                    to: 1
                    duration: 150
                }
                SequentialAnimation {

                    PauseAnimation {
                        duration: 50
                    }
                    NumberAnimation {
                        target: employeeName
                        property: "fieldValueOpacity"
                        to: 1
                        duration: 150
                    }
                }
            }
        }
    }

    function start() {
        revealAnimation.resume();
    }
}
