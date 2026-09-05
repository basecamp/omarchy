import QtQuick

Item {
    Component.onCompleted: {
        try {
            const created = Qt.createQmlObject(
                "import QtQuick; import QtQuick.Effects; MultiEffect {}",
                this,
                "dynamic-effects.qml")
            if (created !== null)
                objectName = "effects-loaded"
        } catch (error) {
        }
    }
}
