import QtQuick

Item {
    Component.onCompleted: {
        const created = Qt.createQmlObject("import QtQuick.Shapes\nShape {}", this,
                                           "dynamic-shapes.qml")
        if (created !== null)
            objectName = "shapes-loaded"
    }
}
