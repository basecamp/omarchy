import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize * 1.18
  height: iconSize
  implicitWidth: iconSize * 1.18
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    scale: 0.95

    Tile { cx: root.width * 0.25; cy: root.height * 0.188 }
    Tile { cx: root.width * 0.75; cy: root.height * 0.188 }
    Tile { cx: root.width * 0.25; cy: root.height * 0.564 }
    Tile { cx: root.width * 0.75; cy: root.height * 0.564 }
    Tile { cx: root.width * 0.50; cy: root.height * 0.812 }
  }

  component Tile: ShapePath {
    property real cx: 0
    property real cy: 0
    readonly property real tileWidth: root.width * 0.50
    readonly property real tileHeight: root.height * 0.376

    fillColor: root.color
    strokeWidth: 0
    startX: cx
    startY: cy - tileHeight / 2
    PathLine { x: cx + tileWidth / 2; y: cy }
    PathLine { x: cx; y: cy + tileHeight / 2 }
    PathLine { x: cx - tileWidth / 2; y: cy }
    PathLine { x: cx; y: cy - tileHeight / 2 }
  }
}
