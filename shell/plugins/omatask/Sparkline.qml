import QtQuick

// History graph for a fixed-capacity series. Newest sample sits at the right
// edge and older ones march left, so a half-full series scrolls in from the
// right instead of stretching to fill and then visibly compressing once the
// buffer wraps.
Canvas {
  id: root

  property var values: []
  // 0 autoscales to the peak in view — right for byte rates, wrong for
  // percentages, where a flat 3% line should sit near the floor rather than
  // being stretched to the ceiling.
  property real maxValue: 100
  // Floor of the plotted range. Percentages start at zero, but a temperature
  // does not — a CPU that idles near 40°C and throttles near 95°C would waste
  // the bottom of the canvas and make idle jitter look dramatic. A floor puts
  // the band that matters across the full height.
  property real minValue: 0
  // Optional reference line, e.g. a thermal limit. 0 draws nothing.
  property real thresholdValue: 0
  property color thresholdColor: stroke
  property int capacity: 0
  property color stroke: "white"
  property real fillOpacity: 0.16
  property real lineWidth: 1.5
  property bool bars: false
  property real barGap: 1
  property bool showBaseline: false

  readonly property int pointCount: (values || []).length
  readonly property int slots: Math.max(2, capacity > 0 ? capacity : pointCount)

  readonly property real scaleMax: {
    if (maxValue > 0) return maxValue
    var peak = 0
    for (var i = 0; i < pointCount; i++) peak = Math.max(peak, Number(values[i]) || 0)
    // A flat-zero series still needs a non-zero divisor.
    return peak > 0 ? peak : 1
  }

  onValuesChanged: requestPaint()
  onStrokeChanged: requestPaint()
  onBarsChanged: requestPaint()
  onMaxValueChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  // Everything else the paint reads. A rendering input without one of these
  // leaves the last frame on screen after the value behind it has changed.
  onMinValueChanged: requestPaint()
  onThresholdValueChanged: requestPaint()
  onThresholdColorChanged: requestPaint()
  onCapacityChanged: requestPaint()
  onFillOpacityChanged: requestPaint()
  onLineWidthChanged: requestPaint()
  onBarGapChanged: requestPaint()
  onShowBaselineChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (width <= 0 || height <= 0 || pointCount === 0) return

    var step = width / (slots - 1)
    var offset = slots - pointCount  // right-align a partially filled series

    function yFor(value) {
      var span = Math.max(1e-6, scaleMax - minValue)
      var normalized = Math.min(1, Math.max(0, ((Number(value) || 0) - minValue) / span))
      // Inset by the stroke so a pegged 100% sample is not clipped in half by
      // the top edge of the canvas.
      var inset = lineWidth / 2
      return inset + (1 - normalized) * Math.max(0, height - lineWidth)
    }

    if (bars) {
      // A bar occupies a slot; a line plot marks the points between them. Using
      // the line's spacing for bars centres the first and last on the canvas
      // edges, so each loses half its width off the side.
      var barStep = width / slots
      var barWidth = Math.max(1, barStep - barGap)
      ctx.fillStyle = stroke
      for (var b = 0; b < pointCount; b++) {
        var top = yFor(values[b])
        ctx.fillRect((offset + b) * barStep, top, barWidth, Math.max(1, height - top))
      }
      return
    }

    ctx.beginPath()
    for (var i = 0; i < pointCount; i++) {
      var px = (offset + i) * step
      var py = yFor(values[i])
      if (i === 0) ctx.moveTo(px, py)
      else ctx.lineTo(px, py)
    }

    if (fillOpacity > 0 && pointCount > 1) {
      ctx.save()
      ctx.lineTo((offset + pointCount - 1) * step, height)
      ctx.lineTo(offset * step, height)
      ctx.closePath()
      ctx.globalAlpha = fillOpacity
      ctx.fillStyle = stroke
      ctx.fill()
      ctx.restore()

      // The fill consumed the path; lay the line down again to stroke it.
      ctx.beginPath()
      for (var j = 0; j < pointCount; j++) {
        var lx = (offset + j) * step
        var ly = yFor(values[j])
        if (j === 0) ctx.moveTo(lx, ly)
        else ctx.lineTo(lx, ly)
      }
    }

    ctx.strokeStyle = stroke
    ctx.lineWidth = lineWidth
    ctx.lineJoin = "round"
    ctx.stroke()

    if (showBaseline) {
      ctx.beginPath()
      ctx.moveTo(0, height - 0.5)
      ctx.lineTo(width, height - 0.5)
      ctx.globalAlpha = 0.25
      ctx.stroke()
    }

    // Reference line last, so it reads on top of the fill.
    if (thresholdValue > minValue && thresholdValue < scaleMax) {
      var ty = Math.round(yFor(thresholdValue)) + 0.5
      ctx.beginPath()
      ctx.setLineDash([3, 3])
      ctx.moveTo(0, ty)
      ctx.lineTo(width, ty)
      ctx.globalAlpha = 0.45
      ctx.lineWidth = 1
      ctx.strokeStyle = thresholdColor
      ctx.stroke()
      ctx.setLineDash([])
    }
  }
}
