import QtQuick

Item {
    id: root

    property int margins: 3

    height: parent.height - 2
    width: parent.height - 2

    CornerFrame {
        anchors {
            fill: parent
            margins: root.margins
        }

        Item {
            anchors.fill: parent
        }
    }
}
