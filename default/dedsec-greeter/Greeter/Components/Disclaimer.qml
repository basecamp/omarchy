import QtQuick
import QtQuick.Layouts

import "../Common"
import "../Config"

RowLayout {
    id: disclaimer
    spacing: 8

    Image {
        id: icon
        source: "../Resources/tesseract.svg"
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
    }

    property string lineOneText: "Property of DedSec. All usage is"
    property int lineOneCharsShown: lineOneText.length
    property string lineTwoText: "subject to tomfoolery."
    property int lineTwoCharsShown: lineTwoText.length

    ColumnLayout {
        id: text

        Layout.fillWidth: true

        Text {
            id: disclaimerText
            Layout.fillWidth: true

            color: Theme.dedsecGray
            font {
                pixelSize: 11
                family: Settings.fontFamily
            }
            fontSizeMode: Text.Fit
            text: disclaimer.lineOneText.substring(0, disclaimer.lineOneCharsShown)
            minimumPixelSize: 1
        }

        Text {
            Layout.fillWidth: true

            color: Theme.dedsecGray

            font {
                pixelSize: 11
                family: Settings.fontFamily
            }
            fontSizeMode: Text.Fit
            text: disclaimer.lineTwoText.substring(0, disclaimer.lineTwoCharsShown)
            minimumPixelSize: 1
        }
    }

    SequentialAnimation {
        id: hideAnimation

        ParallelAnimation {
            NumberAnimation {
                target: disclaimer
                property: "lineTwoCharsShown"
                to: 0
                duration: 300
                easing.type: Easing.InQuart
            }

            SequentialAnimation {
                PauseAnimation {
                    duration: 50
                }

                NumberAnimation {
                    target: disclaimer
                    property: "lineOneCharsShown"
                    to: 0
                    duration: 300
                    easing.type: Easing.InQuart
                }
            }
        }

        PauseAnimation {
            duration: 25
        }

        NumberAnimation {
            target: icon
            property: "opacity"
            to: 0
            duration: 25
        }
    }

    function exit() {
        hideAnimation.start();
    }
}
