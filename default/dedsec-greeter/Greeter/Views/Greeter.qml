import QtQuick
import Quickshell

import "../Config"
import "../Components"
import "../Common"

Variants {
    model: Quickshell.screens

    delegate: Component {
        // qmllint disable
        PanelWindow {
            id: window

            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            color: Theme.background

            exclusionMode: ExclusionMode.Ignore

            focusable: screen.name === Settings.monitor

            Loader {
                active: window.screen.name === Settings.monitor
                anchors.fill: parent
                sourceComponent: MainLayout {}
            }
        }
    }
}
