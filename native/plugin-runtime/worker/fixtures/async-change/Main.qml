import QtQuick

Rectangle {
    id: root
    property bool changed: false
    color: changed ? "#ff2244" : "#2244ff"

    Timer {
        interval: 25
        running: true
        repeat: false
        onTriggered: root.changed = true
    }
}
