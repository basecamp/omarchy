import QtQuick

Item {
  id: root

  required property url frameUrl

  implicitWidth: 320
  implicitHeight: 96

  Image {
    anchors.fill: parent
    source: root.frameUrl
    cache: false
    asynchronous: false
    fillMode: Image.PreserveAspectFit
  }
}
