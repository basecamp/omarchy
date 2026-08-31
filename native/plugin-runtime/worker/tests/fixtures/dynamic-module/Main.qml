import QtQuick

Item {
    Component.onCompleted: {
        try {
            const created = Qt.createQmlObject("import QtQuick.Controls\nButton {}", this,
                                               "dynamic-controls.qml")
            if (created !== null)
                objectName = "controls-loaded"
        } catch (error) {
        }
    }
}
