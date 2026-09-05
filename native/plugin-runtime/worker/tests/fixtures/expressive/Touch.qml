import QtQuick

Rectangle {
    id: root
    width: 64
    height: 32
    color: "#111111"

    property int areaStage: 0
    property int cancelCount: 0
    property int handlerStage: 0

    Rectangle {
        width: 32
        height: parent.height
        color: root.areaStage === 4 && root.cancelCount !== 1 ? "#ff0080"
             : root.areaStage === 1 ? "#ff0000"
             : root.areaStage === 2 ? "#00ff00"
             : root.areaStage === 3 ? "#0000ff"
             : root.areaStage === 4 ? "#ffff00"
             : "#111111"

        MultiPointTouchArea {
            anchors.fill: parent
            minimumTouchPoints: 1
            maximumTouchPoints: 10
            onPressed: function(points) {
                root.cancelCount = 0
                root.areaStage = points.length === 2
                              && Math.round(points[0].x) === 8
                              && Math.round(points[1].x) === 20 ? 1 : 90
            }
            onUpdated: root.areaStage = 2
            onReleased: root.areaStage = 3
            onCanceled: {
                root.cancelCount += 1
                root.areaStage = 4
            }
        }
    }

    Rectangle {
        x: 32
        width: 32
        height: parent.height
        color: root.handlerStage === 1 ? "#ff00ff"
             : root.handlerStage === 2 ? "#00ffff"
             : "#111111"

        PointHandler {
            target: null
            acceptedDevices: PointerDevice.TouchScreen
            onActiveChanged: root.handlerStage = active ? 1 : 2
        }
    }
}
