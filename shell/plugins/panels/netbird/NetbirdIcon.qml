import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false

  // NetBird's mark in its 512 x 372.2 art box, both contours wound the same
  // way: the wings overlap, and disagreeing contours would punch the overlap
  // out into a hole.
  readonly property real markWidth: 512.0
  readonly property real markHeight: 372.2
  readonly property string markPath: "M363.9 0.0 C302.1 5.7 271.4 41.3 259.8 59.3 L254.6 68.4 C254.2 69.2 254.0 69.7 254.0 69.7 L253.9 69.6 L79.1 372.2 L297.1 372.2 L512.0 0.0 Z M368.7 248.4 C336.0 -33.2 -0.0 57.0 -0.0 57.0 L297.1 372.2 Z"

  readonly property real markScale: iconSize / markHeight

  width: markWidth * markScale
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  Item {
    width: root.markWidth
    height: root.markHeight
    transformOrigin: Item.TopLeft
    scale: root.markScale

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4

      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        // Odd-even would punch the overlapping wings into a hole; winding
        // fills it.
        fillRule: ShapePath.WindingFill
        PathSvg { path: root.markPath }
      }
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.1
    height: Math.max(2, root.iconSize * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, root.iconSize * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
