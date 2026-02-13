import QtQuick

import "../Config"

Item {
    id: root

    signal finished

    default property alias content: container.data

    property Animation entranceAnimation: defaultAnimation

    property bool animate: true

    property int startingHorizontalOffset: 0
    property int startingVerticalOffset: 0

    // TODO fix naming of these not accurate
    property int finalHorizontalOffset: 18
    property int finalVerticalOffset: 10

    property int _horizontalOffset: -startingHorizontalOffset - finalHorizontalOffset
    property int _verticalOffset: -startingVerticalOffset - finalVerticalOffset

    property int opacityDuration: 50
    property int opacityEasing: Easing.InCubic

    property int translateDuration: 100
    property int translateEasing: Easing.InCubic

    Item {
        id: container
        anchors.fill: parent
    }

    Image {
        id: accentTopLeft
        source: "../Resources/accent.svg"
        anchors {
            left: root.left
            leftMargin: root._horizontalOffset
            top: root.top
            topMargin: root._verticalOffset
        }
    }

    Image {
        id: accentBotLeft
        source: "../Resources/accent.svg"
        anchors {
            left: root.left
            leftMargin: root._horizontalOffset
            bottom: root.bottom
            bottomMargin: root._verticalOffset
        }
        rotation: 270
    }

    Image {
        id: accentTopRight
        source: "../Resources/accent.svg"
        anchors {
            right: root.right
            rightMargin: root._horizontalOffset
            top: root.top
            topMargin: root._verticalOffset
        }
        rotation: 90
    }

    Image {
        id: accentBotRight
        source: "../Resources/accent.svg"
        anchors {
            right: root.right
            rightMargin: root._horizontalOffset
            bottom: root.bottom
            bottomMargin: root._verticalOffset
        }
        rotation: 180
    }

    ParallelAnimation {
        id: defaultAnimation
        running: Settings.animationProfile(Settings.AnimationMode.All)

        // SECTION Setup

        PropertyAction {
            targets: [accentTopLeft, accentTopRight, accentBotRight, accentBotLeft]
            property: "opacity"
            value: 0
        }
        PropertyAction {
            targets: [accentTopLeft, accentBotLeft]
            property: "anchors.leftMargin"
            value: -root.startingHorizontalOffset
        }
        PropertyAction {
            targets: [accentTopRight, accentBotRight]
            property: "anchors.rightMargin"
            value: -root.startingHorizontalOffset
        }
        PropertyAction {
            targets: [accentTopLeft, accentTopRight]
            property: "anchors.topMargin"
            value: -root.startingVerticalOffset
        }
        PropertyAction {
            targets: [accentBotLeft, accentBotRight]
            property: "anchors.bottomMargin"
            value: -root.startingVerticalOffset
        }

        ScriptAction {
            script: defaultAnimation.pause()
        }

        // SECTION Begin

        // Top Left
        NumberAnimation {
            target: accentTopLeft
            property: "opacity"
            to: 1
            duration: root.opacityDuration
            easing.type: root.opacityEasing
        }
        NumberAnimation {
            target: accentTopLeft
            property: "anchors.leftMargin"
            to: root._horizontalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }
        NumberAnimation {
            target: accentTopLeft
            property: "anchors.topMargin"
            to: root._verticalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }

        // Bottom Left
        NumberAnimation {
            target: accentBotLeft
            property: "opacity"
            to: 1
            duration: root.opacityDuration
            easing.type: root.opacityEasing
        }
        NumberAnimation {
            target: accentBotLeft
            property: "anchors.leftMargin"
            to: root._horizontalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }
        NumberAnimation {
            target: accentBotLeft
            property: "anchors.bottomMargin"
            to: root._verticalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }

        // Top Right
        NumberAnimation {
            target: accentTopRight
            property: "opacity"
            to: 1
            duration: root.opacityDuration
            easing.type: root.opacityEasing
        }
        NumberAnimation {
            target: accentTopRight
            property: "anchors.rightMargin"
            to: root._horizontalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }
        NumberAnimation {
            target: accentTopRight
            property: "anchors.topMargin"
            to: root._verticalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }

        // Bottom Right
        NumberAnimation {
            target: accentBotRight
            property: "opacity"
            to: 1
            duration: root.opacityDuration
            easing.type: root.opacityEasing
        }
        NumberAnimation {
            target: accentBotRight
            property: "anchors.rightMargin"
            to: root._horizontalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }
        NumberAnimation {
            target: accentBotRight
            property: "anchors.bottomMargin"
            to: root._verticalOffset
            duration: root.translateDuration
            easing.type: root.translateEasing
        }

        onFinished: root.finished()
    }

    Component.onCompleted: {
        if (!animate) {
            entranceAnimation.resume();
            entranceAnimation.complete();
        }
    }

    function start() {
        entranceAnimation.resume();
    }
}
