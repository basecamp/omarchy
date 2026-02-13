import QtQuick

import "../Config"
import "../Common"

Item {
    id: root

    signal progressBarMidway
    signal revealFinished
    signal cardFinished

    Accents {
        id: accents
        anchors.fill: parent

        Text {
            id: os
            text: "EC"
            width: parent.width * 0.26  // progress is 0.73 of parent

            TextMetrics {
                id: osMetrics
                font: ct.font
                text: ct.text
            }

            anchors {
                right: parent.right
                baseline: parent.bottom
                baselineOffset: -3
            }

            color: Theme.textPrimary

            font {
                family: Settings.fontFamily
                weight: 300
                pixelSize: 64
            }
            fontSizeMode: Text.Fit
        }

        Rectangle {
            id: progress

            color: Theme.dedsecGray

            anchors.fill: parent

            transformOrigin: Item.Left

            transform: [
                Scale {
                    id: progressX
                    origin.x: 0
                    xScale: 0.73
                },
                Scale {
                    id: progressY
                    origin.y: progress.height / 2
                }
            ]
        }

        Rectangle {
            id: secondaryProgress

            color: Theme.dedsecGray
            anchors.fill: parent

            transform: Scale {
                id: secondaryProgressScale
                origin.x: 0
                xScale: 0
            }
        }

        Text {
            id: ct
            text: "DS"

            width: os.width / 2

            TextMetrics {
                id: ctMetrics
                font: ct.font
                text: ct.text
            }

            anchors {
                left: parent.left
                baseline: parent.bottom
                baselineOffset: -5

                leftMargin: -ctMetrics.tightBoundingRect.x + 0.58 * parent.width
            }
            color: Theme.background
            font {
                family: Settings.fontFamily
                weight: 500
                pixelSize: 34
            }
            fontSizeMode: Text.Fit
        }
    }

    SequentialAnimation {
        id: startupAnimation
        running: Settings.animationProfile(Settings.AnimationMode.All)

        // SECTION Setup
        PropertyAction {
            target: progressX
            property: "xScale"
            value: 0
        }
        PropertyAction {
            target: progressY
            property: "yScale"
            value: 0.7
        }
        PropertyAction {
            targets: [ct, os]
            property: "opacity"
            value: 0
        }

        ScriptAction {
            script: startupAnimation.pause()
        }

        // SECTION Begin

        PauseAnimation {
            duration: 500
        }

        NumberAnimation {
            target: progressX
            property: "xScale"
            to: 0.4
            duration: 700
        }

        ScriptAction {
            script: {
                root.progressBarMidway();
            }
        }

        NumberAnimation {
            target: progressX
            property: "xScale"
            to: 1
            duration: 300
            easing.type: Easing.OutSine
        }

        PauseAnimation {
            duration: 300
        }

        NumberAnimation {
            target: progressY
            property: "yScale"
            to: 1
            duration: 350
            easing.type: Easing.OutCubic
        }

        PauseAnimation {
            duration: 500
        }

        NumberAnimation {
            target: os
            property: "opacity"
            to: 1
            duration: 0
        }

        NumberAnimation {
            target: progressX
            property: "xScale"
            to: 0.73  // percentage of rect in final state
            duration: 300
            easing.type: Easing.OutQuart
        }

        NumberAnimation {
            target: ct
            property: "opacity"
            to: 1
            duration: 100
        }

        onFinished: {
            root.revealFinished();
        }
    }

    SequentialAnimation {
        id: cardAnimation

        ParallelAnimation {
            NumberAnimation {
                target: ct
                property: "opacity"
                to: 0
                duration: 10
            }

            NumberAnimation {
                target: progressX
                property: "xScale"
                to: 1
                duration: 500
                easing.type: Easing.InOutCirc
            }
        }

        PropertyAction {
            target: os
            property: "opacity"
            value: 0
        }

        NumberAnimation {
            target: progress
            property: "opacity"
            to: 0.2
            duration: 500
            easing.type: Easing.InOutCirc
        }

        onFinished: root.cardFinished()
    }

    SequentialAnimation {
        id: finalLoad

        NumberAnimation {
            target: secondaryProgressScale
            property: "xScale"
            duration: 1000
            to: 1
            easing.type: Easing.InCirc
        }
    }

    function start() {
        accents.start();
    }

    Connections {
        target: accents

        function onFinished() {
            startupAnimation.resume();
        }
    }

    function startCard() {
        cardAnimation.start();
    }

    function startFinal() {
        finalLoad.start();
    }
}
