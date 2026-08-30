import QtQuick

Item {
    Repeater {
        model: 5000
        delegate: Item {}
    }
}
