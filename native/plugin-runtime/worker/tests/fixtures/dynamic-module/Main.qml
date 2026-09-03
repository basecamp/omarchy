import QtQuick

Item {
    Component.onCompleted: {
        try {
            const created = Qt.createQmlObject("import QtQuick.Dialogs\nFileDialog {}", this,
                                               "dynamic-dialog.qml")
            if (created !== null)
                objectName = "dialog-loaded"
        } catch (error) {
        }
    }
}
