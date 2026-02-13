import QtQuick

import "../Common"

Row {
    id: root

    Item {
        id: ct
        height: parent.height
        width: 105

        Rectangle {
            color: Theme.dedsecGray
            anchors.fill: parent
        }

        Image {
            source: "../Resources/distro-arch.svg"

            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: 8
            }

            height: root.height * 0.8
            width: root.height * 0.8
        }

        Text {
            text: "CT"

            anchors {
                right: ct.right
                rightMargin: 2
                baseline: ct.bottom
                baselineOffset: -5
            }

            color: Theme.background

            font {
                pixelSize: 22
                family: Settings.fontFamily
                weight: 500
            }
        }
    }

    Text {
        anchors {
            verticalCenter: root.verticalCenter
        }

        color: Theme.dedsecGray

        font {
            family: Settings.fontFamily
            pixelSize: 36
            weight: 300
        }
        text: "OS"
        rightPadding: 2
    }
}
