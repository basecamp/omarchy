import QtQuick
import Quickshell

import "../Common"
import "../Config"

Item {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Row {

        spacing: 20

        Accents {
            id: accents

            width: 110
            height: 110

            opacityDuration: 200
            translateDuration: 300

            startingHorizontalOffset: -20
            startingVerticalOffset: -20
            finalHorizontalOffset: 20
            finalVerticalOffset: 20

            Image {
                id: logo
                anchors.fill: parent
                source: "../Resources/os-icon.svg"
            }
        }

        Column {

            spacing: 12

            Text {
                id: time

                color: Theme.textPrimaryDimmer

                text: Qt.formatDateTime(clock.date, "hh:mm")

                font {
                    pixelSize: 48
                    weight: 100
                    family: Settings.fontFamily
                }

                transform: Translate {
                    id: timeTranslate
                }
            }

            Rectangle {
                id: region

                width: regionLabel.width + 24
                height: regionLabel.height + 6

                border {
                    color: "#414141"
                    width: 1
                }

                color: "transparent"

                transform: Translate {
                    id: regionTranslate
                }

                Text {
                    id: regionLabel

                    anchors {
                        verticalCenter: parent.verticalCenter
                        verticalCenterOffset: 2
                        left: parent.left
                        leftMargin: 8
                    }

                    color: "#B1B1B1"
                    // text: "AU-SOUTH-EAST-2"
                    text: Qt.formatDateTime(clock.date, "dddd dd MMMM")
                    font {
                        pixelSize: 14
                        family: Settings.fontFamily
                        weight: 300
                    }
                }
            }
        }
    }

    SequentialAnimation {
        id: revealAnimation
        running: Settings.animationProfile(Settings.AnimationMode.All)

        PropertyAction {
            targets: [logo, time, region]
            property: "opacity"
            value: 0
        }

        PropertyAction {
            targets: [timeTranslate, regionTranslate]
            property: "y"
            value: -10
        }

        ScriptAction {
            script: revealAnimation.pause()
        }

        PauseAnimation {
            duration: 100
        }

        ParallelAnimation {
            // Logo
            NumberAnimation {
                target: logo
                property: "opacity"
                to: 1
                duration: 300
                easing.type: Easing.InExpo
            }

            SequentialAnimation {

                PauseAnimation {
                    duration: 100
                }
                ParallelAnimation {

                    // Time
                    NumberAnimation {
                        target: time
                        property: "opacity"
                        to: 1
                        duration: 300
                        easing.type: Easing.InExpo
                    }

                    NumberAnimation {
                        target: timeTranslate
                        property: "y"
                        to: 0
                        duration: 300
                        easing.type: Easing.InExpo
                    }
                }
            }

            SequentialAnimation {

                PauseAnimation {
                    duration: 200
                }
                ParallelAnimation {

                    NumberAnimation {
                        target: region
                        property: "opacity"
                        to: 1
                        duration: 300
                        easing.type: Easing.InExpo
                    }

                    NumberAnimation {
                        target: regionTranslate
                        property: "y"
                        to: 0
                        duration: 300
                        easing.type: Easing.InExpo
                    }
                }
            }
        }
    }

    Connections {
        target: accents

        function onFinished() {
            revealAnimation.resume();
        }
    }

    function start() {
        accents.start();
    }
}
