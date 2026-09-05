import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

// One image clipped to the carousel's leaning quad. The lean belongs to the
// column rather than the quad: `columnTop` places this quad inside a column
// `columnHeight` tall, so a short band leans like the tall preview above it.
Item {
  id: root

  property string source: ""
  property real skewOffset: 0
  property real columnHeight: height
  property real columnTop: 0
  property real dimOpacity: 0
  property color dimColor: "black"
  property color borderColor: "transparent"
  property int borderWidth: 0

  readonly property real skewAbs: Math.abs(skewOffset)
  readonly property real span: width - skewAbs

  function leftAt(offset) {
    var progress = columnHeight > 0 ? offset / columnHeight : 0
    return skewOffset >= 0 ? skewAbs * (1 - progress) : skewAbs * progress
  }

  readonly property real topLeft: leftAt(columnTop)
  readonly property real bottomLeft: leftAt(columnTop + height)
  readonly property real topRight: topLeft + span
  readonly property real bottomRight: bottomLeft + span

  Item {
    id: maskShape
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "white"
        strokeColor: "transparent"
        startX: root.topLeft; startY: 0
        PathLine { x: root.topRight; y: 0 }
        PathLine { x: root.bottomRight; y: root.height }
        PathLine { x: root.bottomLeft; y: root.height }
        PathLine { x: root.topLeft; y: 0 }
      }
    }
  }

  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: maskShape
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

    Image {
      anchors.fill: parent
      source: root.source ? Util.fileUrl(root.source) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: false
      cache: true
      smooth: true
    }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(root.dimColor, root.dimOpacity)
    }
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.borderColor
      strokeWidth: root.borderWidth
      startX: root.topLeft; startY: 0
      PathLine { x: root.topRight; y: 0 }
      PathLine { x: root.bottomRight; y: root.height }
      PathLine { x: root.bottomLeft; y: root.height }
      PathLine { x: root.topLeft; y: 0 }
    }
  }
}
