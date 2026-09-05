import QtQuick

Item {
    id: root
    Component.onCompleted: {
        const created = Qt.createQmlObject("import QtQuick.Controls\nButton { text: 'dynamic' }", root,
                                           "dynamic-controls.qml")
        objectName = created.text + "-loaded"
    }
}
