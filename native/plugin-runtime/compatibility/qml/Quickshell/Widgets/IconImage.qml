import QtQuick

Item {
  id: root

  property alias source: image.source
  property alias asynchronous: image.asynchronous
  property alias status: image.status
  property alias mipmap: image.mipmap
  property alias backer: image
  property real implicitSize: 0
  readonly property real actualSize: Math.min(width, height)

  implicitWidth: implicitSize
  implicitHeight: implicitSize

  Image {
    id: image
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    sourceSize.width: root.actualSize
    sourceSize.height: root.actualSize
  }
}
