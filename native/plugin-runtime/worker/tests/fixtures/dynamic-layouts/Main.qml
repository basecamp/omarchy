import QtQuick

Item {
    Component.onCompleted: {
        try {
            const created = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Layouts; RowLayout {}",
                this,
                "dynamic-layouts.qml")
            if (created !== null)
                objectName = "layouts-loaded"
        } catch (error) {
        }
    }
}
