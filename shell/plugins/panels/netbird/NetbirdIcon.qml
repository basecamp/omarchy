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

  // Renders the NetBird logomark natively via Canvas to avoid tiny-SVG
  // rendering quirks in bar slots. The mark is a geometric bird/wing made
  // of three orange shapes, drawn here in the theme foreground color so it
  // adapts to light/dark bars like other Omarchy widgets.
  Canvas {
    id: canvas
    anchors.fill: parent
    property real sx: root.iconSize / 512
    property real sy: root.iconSize / 372
    property color drawColor: root.color

    onDrawColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      // Scale the 512×372 viewBox into the icon's square slot, centered.
      var vw = 512
      var vh = 372
      var scale = Math.min(root.iconSize / vw, root.iconSize / vh)
      var ox = (root.iconSize - vw * scale) / 2
      var oy = (root.iconSize - vh * scale) / 2

      ctx.translate(ox, oy)
      ctx.scale(scale, scale)
      ctx.translate(-0.02, -69.9)

      ctx.fillStyle = drawColor

      // Path 1: Outer wing — large triangle from top-right to bottom-left.
      ctx.beginPath()
      ctx.moveTo(364.3, 68)
      ctx.bezierCurveTo(302.5, 73.7, 271.8, 109.3, 260.2, 127.3)
      ctx.lineTo(255, 136.4)
      ctx.bezierCurveTo(254.6, 137.2, 254.4, 137.9, 254.4, 137.9)
      ctx.lineTo(254.3, 137.8)
      ctx.lineTo(79.5, 440.2)
      ctx.lineTo(297.5, 440.2)
      ctx.lineTo(512.4, 68)
      ctx.closePath()
      ctx.fill()

      // Path 2: Lower swoosh — curved bottom shape.
      ctx.beginPath()
      ctx.moveTo(297.5, 440.2)
      ctx.lineTo(0.4, 125)
      ctx.bezierCurveTo(0.4, 125, 336.4, 34.8, 369.1, 316.4)
      ctx.closePath()
      ctx.fill()

      // Path 3: Inner accent — darker orange in the original, drawn here in
      // a slightly transparent overlay of the same color for depth.
      ctx.globalAlpha = 0.7
      ctx.beginPath()
      ctx.moveTo(253.5, 138.9)
      ctx.lineTo(162.3, 296.8)
      ctx.lineTo(297.5, 440.2)
      ctx.lineTo(369.1, 316.2)
      ctx.bezierCurveTo(357.8, 219.3, 310.6, 166.5, 253.5, 138.9)
      ctx.closePath()
      ctx.fill()
      ctx.globalAlpha = 1.0
    }
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
}