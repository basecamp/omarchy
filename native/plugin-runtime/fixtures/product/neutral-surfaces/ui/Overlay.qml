import QtQuick

Rectangle {
    id: root

    property bool opened: false

    width: 400
    height: 240
    color: "#647052"

    function open() {
        opened = true
    }

    function close() {
        opened = false
    }

}
