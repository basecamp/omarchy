import QtQuick
import qs.Commons
import "Model.js" as Model

// Labelled horizontal fill bar: caption on the left, reading on the right,
// track underneath. Used for memory, swap, and the CPU summary so all three
// read as one family.
Column {
  id: root

  // Dimming has to know what it is dimming *against*. dim() only reads as
  // "less prominent" on a dark ground; on a light theme it makes secondary text
  // darker — and therefore louder — than the primary text it sits behind. This
  // moves toward the background either way.
  readonly property bool groundIsDark: Model.groundIsDark(root.ground)
  function dim(c, amount) { return Model.dim(root.ground, c, amount) }

  // The surface this sits on, so dim() knows which way to move.
  property color ground: Color.popups.background

  property string label: ""
  property string value: ""
  property real fraction: 0
  property color foreground: Color.foreground
  property color fill: foreground
  property string fontFamily: Style.font.family
  property real trackHeight: Style.space(6)
  property bool compact: false

  spacing: Style.spacing.labelGap
  width: parent ? parent.width : implicitWidth

  Item {
    width: parent.width
    height: caption.implicitHeight
    visible: root.label !== "" || root.value !== ""

    Text {
      id: caption
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: dim(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: root.compact ? Style.font.caption : Style.font.bodySmall
      font.bold: true
      font.letterSpacing: 0.8
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.compact ? Style.font.caption : Style.font.bodySmall
    }
  }

  Rectangle {
    id: track
    width: parent.width
    height: root.trackHeight
    radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

    Rectangle {
      height: parent.height
      radius: parent.radius
      color: root.fill
      // Clamp rather than trusting the caller: a rate-derived fraction can
      // briefly exceed 1 between samples and would otherwise overhang the
      // track. A true zero paints nothing — the rounded minimum width would
      // otherwise leave a permanent dot on an unused swap meter.
      width: root.fraction <= 0
        ? 0
        : Math.max(height, parent.width * Math.min(1, root.fraction))

      Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 200 } }
    }
  }
}
