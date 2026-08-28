import QtQuick

Item {
    width: 64
    height: 32

    Rectangle {
        anchors.fill: parent
        color: "#ff2d55"
    }

    Component.onCompleted: {
        console.info("native-build-probe: QML module loaded", width, height)
        Qt.callLater(Qt.quit)
    }
}
