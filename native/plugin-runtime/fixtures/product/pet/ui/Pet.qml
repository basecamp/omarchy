import QtQuick

Item {
    id: root
    width: 320
    height: 180

    readonly property string surfaceRole: "desktop-overlay"
    readonly property bool acceptsKeyboardFocus: false
    readonly property int maximumFramesPerSecond: 30
    property real petX: 20
    property bool walking: false
    property var inputRegions: [{x: petX, y: 104, width: 76, height: 58}]

    function stepForTest() {
        petX = Math.min(width - 78, petX + 24)
        inputRegions = [{x: petX, y: 104, width: 76, height: 58}]
    }

    Rectangle {
        id: shadow
        x: root.petX + 8
        y: 153
        width: 62
        height: 10
        radius: 5
        color: "#33000000"
    }

    Item {
        id: pet
        x: root.petX
        y: 104
        width: 76
        height: 58

        Rectangle {
            x: 10
            y: 17
            width: 58
            height: 36
            radius: 18
            color: "#e7b66c"
            border.color: "#6e462f"
            border.width: 2
        }

        Rectangle {
            x: 45
            y: 6
            width: 27
            height: 30
            radius: 13
            color: "#efc37c"
            border.color: "#6e462f"
            border.width: 2
        }

        Text {
            x: 54
            y: 10
            text: "•ᴥ•"
            color: "#342219"
            font.pixelSize: 10
        }

        Rectangle {
            x: 15
            y: 48
            width: 12
            height: 7
            radius: 3
            color: "#6e462f"
        }

        Rectangle {
            x: 49
            y: 48
            width: 12
            height: 7
            radius: 3
            color: "#6e462f"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.walking = !root.walking
        }
    }

    NumberAnimation on petX {
        running: root.walking
        from: 20
        to: root.width - 78
        duration: 3200
        loops: Animation.Infinite
        easing.type: Easing.InOutQuad
    }
}
