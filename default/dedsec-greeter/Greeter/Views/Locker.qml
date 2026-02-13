import Quickshell.Wayland
import QtQuick

import "../Services"
import "../Config"
import "../Components"

WlSessionLock {
    id: lock

    locked: AuthManager.state !== AuthManager.State.Finish

    WlSessionLockSurface {
        id: lockSurface

        Rectangle {
            anchors.fill: parent
            color: "#ff050a0e"
        }

        Loader {
            // race condition where lockSurface.screen isn't available yet
            active: lockSurface.screen ? lockSurface.screen.name === Settings.monitor : false
            anchors.fill: parent
            sourceComponent: MainLayout {}
        }
    }
}
