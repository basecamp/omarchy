import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real dotSize: Math.max(2, root.iconSize * 0.24)
  readonly property real mid: (root.iconSize - dotSize) / 2
  readonly property real end: root.iconSize - dotSize

  // Native rendering of the Tailscale mark from the SVG: a 3×3 dot grid
  // with the inactive dots faded. This avoids Qt SVG/effect rendering quirks
  // in tiny bar slots while keeping the official silhouette.
  Dot { x: 0; y: 0; opacity: 0.24 }
  Dot { x: root.mid; y: 0; opacity: 0.24 }
  Dot { x: root.end; y: 0; opacity: 0.24 }
  Dot { x: 0; y: root.mid; opacity: 1.0 }
  Dot { x: root.mid; y: root.mid; opacity: 1.0 }
  Dot { x: root.end; y: root.mid; opacity: 1.0 }
  Dot { x: 0; y: root.end; opacity: 0.24 }
  Dot { x: root.mid; y: root.end; opacity: 1.0 }
  Dot { x: root.end; y: root.end; opacity: 0.24 }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
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

  component Dot: Rectangle {
    width: root.dotSize
    height: root.dotSize
    radius: width / 2
    color: root.color
  }
}
