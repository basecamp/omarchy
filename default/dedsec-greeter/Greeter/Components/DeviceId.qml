import QtQuick
import QtQuick.Layouts

import "../Config"
import "../Common"

Row {

    ColumnLayout {
        id: aside

        transform: Translate {
            id: asideTranslate
        }

        anchors {
            top: parent.top
            topMargin: 5 * Units.vh
            bottom: parent.bottom
        }
        width: 35 * Units.vh

        Image {
            id: tesseract
            source: "../Resources/tesseract.svg"
            Layout.preferredHeight: deviceText.width + 2
            Layout.preferredWidth: deviceText.width + 2

            transform: Translate {
                id: tesseractTranslate
            }
        }
        Item {
            // spacer
            Layout.fillHeight: true
        }

        Image {
            id: deviceText
            source: "../Resources/device-text.svg"

            Layout.bottomMargin: 5
            Layout.topMargin: 20 * Units.vh
            Layout.fillHeight: true

            fillMode: Image.PreserveAspectFit

            transform: Translate {
                id: deviceTextTranslate
            }
        }

        Rectangle {
            id: borderRect
            height: 3

            Layout.fillWidth: true

            color: Theme.textPrimaryDim
        }
    }

    Image {
        id: barcode
        z: 3

        anchors {
            top: parent.top
            bottom: parent.bottom
        }

        fillMode: Image.PreserveAspectFit

        source: "../Resources/device-barcode.svg"
    }

    SequentialAnimation {
        id: revealAnimation
        running: Settings.animationProfile(Settings.AnimationMode.All)

        // SECTION Setup
        PropertyAction {
            targets: [barcode, borderRect]
            property: "opacity"
            value: 0
        }
        PropertyAction {
            targets: [tesseract, deviceText]
            property: "opacity"
            value: 0
        }
        PropertyAction {
            targets: [tesseractTranslate, deviceTextTranslate]
            property: "x"
            value: 10
        }

        ScriptAction {
            script: revealAnimation.pause()
        }

        // SECTION Animation
        NumberAnimation {
            targets: [barcode, borderRect]
            property: "opacity"
            to: 1
            duration: 300
            easing.type: Easing.InBounce
        }

        ParallelAnimation {
            NumberAnimation {
                target: tesseract
                property: "opacity"
                to: 1
                duration: 300
                easing.type: Easing.InExpo
            }
            NumberAnimation {
                target: tesseractTranslate
                property: "x"
                to: 0
                duration: 300
                easing.type: Easing.InExpo
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: deviceText
                property: "opacity"
                to: 1
                duration: 300
                easing.type: Easing.InExpo
            }
            NumberAnimation {
                target: deviceTextTranslate
                property: "x"
                to: 0
                duration: 300
                easing.type: Easing.InExpo
            }
        }
    }

    function start() {
        revealAnimation.resume();
    }
}
