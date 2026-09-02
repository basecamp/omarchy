import QtQuick
import QtQuick.Shapes
import qs.Commons
import "../Commons/BorderGeometry.js" as Geometry

// Visual-only rounded surface fill for shell color specs containing gradients.
// Solid fills stay on Rectangle.color; this Shape exists only for 2+ stops.
Item {
  id: root

  property var fillSpec: null
  property real radius: 0

  readonly property var _gradient: fillSpec && fillSpec.gradient
    ? fillSpec.gradient
    : ({ colors: [], angle: 0, enabled: false })
  readonly property var _colors: _gradient.colors || []
  readonly property var _endpoints: Geometry.gradientEndpoints(width, height, _gradient.angle || 0)
  readonly property string _path: Geometry.roundedRectPath(0, 0, width, height, {
    tlrx: radius, tlry: radius,
    trrx: radius, trry: radius,
    brrx: radius, brry: radius,
    blrx: radius, blry: radius,
  })

  visible: _gradient.enabled && width > 0 && height > 0

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: 0
      fillGradient: LinearGradient {
        x1: root._endpoints.x1
        y1: root._endpoints.y1
        x2: root._endpoints.x2
        y2: root._endpoints.y2

        GradientStop { position: Geometry.sampledStopPosition(0, 10); color: Geometry.sampledStopColor(root._colors, 0, 10) }
        GradientStop { position: Geometry.sampledStopPosition(1, 10); color: Geometry.sampledStopColor(root._colors, 1, 10) }
        GradientStop { position: Geometry.sampledStopPosition(2, 10); color: Geometry.sampledStopColor(root._colors, 2, 10) }
        GradientStop { position: Geometry.sampledStopPosition(3, 10); color: Geometry.sampledStopColor(root._colors, 3, 10) }
        GradientStop { position: Geometry.sampledStopPosition(4, 10); color: Geometry.sampledStopColor(root._colors, 4, 10) }
        GradientStop { position: Geometry.sampledStopPosition(5, 10); color: Geometry.sampledStopColor(root._colors, 5, 10) }
        GradientStop { position: Geometry.sampledStopPosition(6, 10); color: Geometry.sampledStopColor(root._colors, 6, 10) }
        GradientStop { position: Geometry.sampledStopPosition(7, 10); color: Geometry.sampledStopColor(root._colors, 7, 10) }
        GradientStop { position: Geometry.sampledStopPosition(8, 10); color: Geometry.sampledStopColor(root._colors, 8, 10) }
        GradientStop { position: Geometry.sampledStopPosition(9, 10); color: Geometry.sampledStopColor(root._colors, 9, 10) }
      }

      PathSvg { path: root._path }
    }
  }
}
