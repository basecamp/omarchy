import QtQuick
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property color trackColor: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "#333"
  property color fillColor: bar ? bar.foreground : Color.foreground
  property color knobColor: bar ? bar.foreground : Color.foreground
  property bool dragging: false
  property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
  property real liveValue: value

  // Used for a "muted"/disabled look. The knob's *color* is dimmed (blended
  // toward the panel background) rather than its opacity, and stays fully
  // opaque -- an opacity fade would make the knob semi-transparent and stop
  // it from fully covering the fill/track boundary beneath it, letting that
  // seam show through the middle of the knob. Blending the solid color
  // instead keeps the knob 100% opaque (no seam).
  //
  // The dimmed fill line itself isn't a flat color -- it's the track (drawn
  // at 0.5 opacity over the background) with the fill drawn on top of that
  // (also at 0.5 opacity). Both trackColor and fillColor can carry their own
  // alpha (trackColor especially -- Style.selectedFillFor(...) is typically
  // a translucent color), so the *effective* alpha at each step is the
  // color's own alpha times the Rectangle's 0.5 opacity, not just 0.5. We
  // replicate that two-step over-compositing here (background -> track ->
  // fill) so the muted knob lands on exactly the same composited color as
  // the muted line, instead of reading brighter than it.
  property bool dimmed: false
  readonly property color _dimBackdrop: bar ? bar.background : "#101315"

  readonly property real _dimTrackAlpha: trackColor.a * 0.5
  readonly property real _dimFillAlpha: fillColor.a * 0.5

  readonly property color _dimTrackOverBackdrop: Qt.rgba(
    _dimBackdrop.r * (1 - _dimTrackAlpha) + trackColor.r * _dimTrackAlpha,
    _dimBackdrop.g * (1 - _dimTrackAlpha) + trackColor.g * _dimTrackAlpha,
    _dimBackdrop.b * (1 - _dimTrackAlpha) + trackColor.b * _dimTrackAlpha,
    1)

  readonly property color _dimmedLineColor: Qt.rgba(
    _dimTrackOverBackdrop.r * (1 - _dimFillAlpha) + fillColor.r * _dimFillAlpha,
    _dimTrackOverBackdrop.g * (1 - _dimFillAlpha) + fillColor.g * _dimFillAlpha,
    _dimTrackOverBackdrop.b * (1 - _dimFillAlpha) + fillColor.b * _dimFillAlpha,
    1)

  readonly property color effectiveKnobColor: dimmed ? _dimmedLineColor : knobColor

  // macOS-style notches. When > 1, that many evenly-spaced tick marks are cut
  // into the track (drawn in the panel background color, so only the part
  // crossing the track shows). Purely visual — snapping is the caller's job via
  // `integer`/`step` or an index-based value. Default 0 leaves the track plain.
  property int tickCount: 0
  property color tickColor: bar ? bar.background : Color.background

  onValueChanged: if (!dragging) liveValue = value

  signal moved(real value)
  signal released(real value)

  // Right-click is a secondary action on the whole track — audio uses it to
  // mute the channel the slider belongs to. Dragging stays left-button only.
  signal rightClicked()

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.md)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property bool _hot: mouseArea.containsMouse || root.dragging

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.trackHeight
    radius: height / 2
    color: root.trackColor
    opacity: root.dimmed ? 0.5 : 1.0
  }

  Rectangle {
    id: fill
    anchors.verticalCenter: track.verticalCenter
    anchors.left: track.left
    height: track.height
    radius: track.radius
    color: root.fillColor
    width: track.width * root.progress
    opacity: root.dimmed ? 0.5 : 1.0

    Behavior on width {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  Repeater {
    model: root.tickCount > 1 ? root.tickCount : 0
    Rectangle {
      required property int index
      width: Math.max(1, Style.space(2))
      height: root.trackHeight + Style.space(4)
      radius: 1
      color: root.tickColor
      opacity: root.dimmed ? 0.5 : 1.0
      anchors.verticalCenter: track.verticalCenter
      x: Math.max(0, Math.min(track.width - width,
                              track.width * (index / (root.tickCount - 1)) - width / 2))
    }
  }

  BorderSurface {
    id: knob
    width: root.knobSize
    height: root.knobSize
    radius: root.knobSize / 2
    color: root.effectiveKnobColor
    borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
    scale: root._hot ? 1.15 : 1.0

    Behavior on x {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x))
      var raw = root.minimum + (clamped / track.width) * root.range
      if (root.integer) raw = Math.round(raw)
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = true
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.rightClicked()
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onWheel: function(wheel) {
      var delta = wheel.angleDelta.y > 0 ? root.step : -root.step
      var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + delta))
      if (root.integer) next = Math.round(next)
      root.liveValue = next
      root.moved(next)
      root.released(next)
    }
  }
}
