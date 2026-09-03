import QtQuick
import QtQuick.Effects 6.5

Item {
    objectName: "trusted-effects"

    MultiEffect {
        source: Rectangle { width: 12; height: 12 }
        blurEnabled: true
        blur: 0.5
    }
}
