import QtQuick

Rectangle {
    id: root

    property bool opened: false

    width: 320
    height: 480
    color: "#7a6652"

    function open() {
        opened = true
    }

    function close() {
        opened = false
    }

}
