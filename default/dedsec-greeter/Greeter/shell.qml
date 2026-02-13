import Quickshell

import QtQuick

import "Views"
import "Config"

Scope {
    id: greeter

    Loader {
        active: Settings.isDebug || Settings.isTest
        anchors.fill: parent
        sourceComponent: Tester {}
    }

    Loader {
        active: Settings.isGreetd
        anchors.fill: parent
        sourceComponent: Greeter {}
    }

    Loader {
        active: Settings.isLockd
        anchors.fill: parent
        sourceComponent: Locker {}
    }
}
