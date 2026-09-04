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
  property bool spinning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Canvas {
    id: mark
    anchors.fill: parent

    RotationAnimation on rotation {
      running: root.spinning
      from: 0
      to: 360
      duration: 1600
      loops: Animation.Infinite
    }

    onPaint: {
      var context = getContext("2d")
      var center = width / 2
      var stroke = Math.max(1.1, width * 0.085)
      var radius = center - stroke
      var nodeRadius = Math.max(1.35, width * 0.11)
      var hub = { x: center + radius * 0.4, y: center }
      var nodes = [
        { x: center + radius, y: center },
        { x: center - radius * 0.74, y: center - radius * 0.67 },
        { x: center - radius * 0.74, y: center + radius * 0.67 }
      ]

      context.clearRect(0, 0, width, height)
      context.strokeStyle = root.color
      context.fillStyle = root.color
      context.lineWidth = stroke
      context.lineCap = "round"
      context.beginPath()
      context.arc(center, center, radius, 0, 2 * Math.PI)
      context.stroke()

      for (var i = 0; i < nodes.length; i++) {
        context.beginPath()
        context.moveTo(hub.x, hub.y)
        context.lineTo(nodes[i].x, nodes[i].y)
        context.stroke()
      }
      context.beginPath()
      context.arc(hub.x, hub.y, nodeRadius, 0, 2 * Math.PI)
      context.fill()
      for (var j = 0; j < nodes.length; j++) {
        context.beginPath()
        context.arc(nodes[j].x, nodes[j].y, nodeRadius, 0, 2 * Math.PI)
        context.fill()
      }
    }
  }

  onColorChanged: mark.requestPaint()
  onWidthChanged: mark.requestPaint()
  onSpinningChanged: if (!spinning) mark.rotation = 0

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
