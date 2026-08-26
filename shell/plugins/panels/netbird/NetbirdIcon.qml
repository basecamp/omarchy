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

  readonly property real dotSize: Math.max(2, root.iconSize * 0.26)
  readonly property real hubSize: Math.max(2, root.iconSize * 0.3)
  readonly property real spoke: (root.iconSize - dotSize) / 2
  readonly property real linkWidth: Math.max(1, root.iconSize * 0.1)

  // A mesh drawn natively rather than an SVG: one hub with three peers, which
  // is what NetBird is and what survives being rendered at bar size. Tiny SVGs
  // pick up Qt rendering quirks in a bar slot, so the Tailscale widget next
  // door draws its mark the same way.
  Link { angle: -90 }
  Link { angle: 30 }
  Link { angle: 150 }

  Peer { angle: -90 }
  Peer { angle: 30 }
  Peer { angle: 150 }

  Rectangle {
    width: root.hubSize
    height: root.hubSize
    radius: width / 2
    color: root.color
    anchors.centerIn: parent
  }

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

  // Anchored at the icon's centre and rotated outward, so the spoke always
  // starts at the hub whatever size the bar hands us.
  component Link: Rectangle {
    required property real angle

    width: root.spoke
    height: root.linkWidth
    radius: height / 2
    color: root.color
    opacity: 0.45
    x: root.iconSize / 2
    y: (root.iconSize - height) / 2
    transformOrigin: Item.Left
    rotation: angle
  }

  component Peer: Rectangle {
    required property real angle

    width: root.dotSize
    height: root.dotSize
    radius: width / 2
    color: root.color
    x: (root.iconSize - root.dotSize) / 2 + root.spoke * Math.cos(angle * Math.PI / 180)
    y: (root.iconSize - root.dotSize) / 2 + root.spoke * Math.sin(angle * Math.PI / 180)
  }
}
