import Quickshell
import QtQuick

import "./Common"
import "./Components"

// qmllint disable
PanelWindow {
    id: root

    color: Theme.background

    implicitHeight: 37

    anchors {
        top: true
        right: true
        left: true
    }

    Rectangle {
        anchors.fill: parent
        border {
            width: 1
            color: Theme.dedsecGray
        }
        color: "transparent"
    }

    Row {
        anchors.fill: parent

        SystemLabel {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }

        Divider {}

        Workspace {}

        Divider {}
    }
}
