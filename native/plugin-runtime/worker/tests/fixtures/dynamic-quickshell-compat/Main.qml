import QtQuick

Item {
  id: root
  Component.onCompleted: {
    const created = Qt.createQmlObject(
      "import QtQuick; import Quickshell.Widgets 1.0; WrapperRectangle { margin: 2; Rectangle { implicitWidth: 3; implicitHeight: 3 } }",
      root,
      "dynamic-quickshell-compat.qml")
    objectName = created.child !== null ? "dynamic-quickshell-compat-loaded" : "dynamic-quickshell-compat-incomplete"
  }
}
