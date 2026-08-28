import QtQuick
import QtQuick.Window
import qs.Commons

// Places a font glyph by the bounds of its ink instead of its line box, and
// with `normalize` on sizes the font so that ink fills the item. The font's
// tight bounding rect gets it within a pixel; the rendered pixels are then
// measured and the size and position corrected until the glyph meets the
// shared icon rules, so unlike icons come out at one optical size, centered
// on the same point.
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property color color: Color.foreground
  property bool normalize: false
  property bool debugBounds: false

  readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))
  readonly property real baseInkWidth: Math.max(1, baseMetrics.tightBoundingRect.width)
  readonly property real baseInkHeight: Math.max(1, baseMetrics.tightBoundingRect.height)
  // The mark measured once on its own, at a reference size, in a box far
  // larger than it needs. Every render the fit looks at is grabbed at the size
  // of the canvas, so ink reaching past it is cut off by the grab and measures
  // as exactly the canvas — which is what made earlier attempts at this
  // quietly do nothing at all. Measured here, nothing can be cut off and
  // nothing depends on the canvas, so the size to render at and how far to
  // condense are arithmetic rather than a hunt. Cached per glyph and family.
  // Kept small on purpose: this is one render per distinct glyph at shell
  // start, and every pixel of it is time the bar is not up yet. It only has
  // to be big enough to measure ratios, not to look at.
  readonly property int probePixelSize: 40
  property var probeInk: null
  readonly property real naturalAspect: probeInk && probeInk.aspect > 0
    ? probeInk.aspect : baseInkWidth / baseInkHeight
  readonly property real inkWidthRatio: probeInk && probeInk.widthRatio > 0
    ? probeInk.widthRatio : baseInkWidth / renderedFontSize
  readonly property real inkHeightRatio: probeInk && probeInk.heightRatio > 0
    ? probeInk.heightRatio : baseInkHeight / renderedFontSize
  readonly property real inkCoverage: probeInk && probeInk.coverage > 0 ? probeInk.coverage : 0

  // Sized so the mark's ink fills the block across the bar.
  readonly property real inkWidthPixels: Math.max(0.0001, inkWidthRatio * renderedFontSize)
  readonly property real inkHeightPixels: Math.max(0.0001, inkHeightRatio * renderedFontSize)
  // Scaled until the ink meets whichever edge comes first, then nudged by how
  // densely it is inked so a solid mark does not loom over a hairline one.
  // Fitted by the middle of the mark's two dimensions and nudged for density,
  // then held so it can never outgrow the canvas that has to hold it.
  readonly property real block: Math.min(width, height)
  readonly property real rawMetricScale: normalize && width > 0 && height > 0
    ? Math.min(
        IconRules.meanFit(inkWidthPixels, inkHeightPixels, block) * IconRules.weightFit(inkCoverage),
        Math.min(width / inkWidthPixels, height / inkHeightPixels))
    : 1
  // However the measurement came out, a glyph is never drawn far larger than
  // the canvas that has to hold it. Belt and braces: the band above should
  // already have caught anything this would clamp.
  readonly property real metricScaleCeiling: normalize && renderedFontSize > 0
    ? (2.5 * Math.max(width, height)) / renderedFontSize
    : 1
  readonly property real metricScale: normalize
    ? Math.min(rawMetricScale, metricScaleCeiling)
    : 1
  // A mark wider than the block is condensed toward square rather than shrunk,
  // so it keeps the row's height instead of reading half of it.

  // Corrections the measured pixels asked for, on top of the metric estimate.
  property real pixelScale: 1
  property real pixelOffsetX: 0
  property real pixelOffsetY: 0
  readonly property real normalizedScale: metricScale * pixelScale
  readonly property real tightWidth: baseInkWidth * normalizedScale
  readonly property real tightHeight: baseInkHeight * normalizedScale

  // A normalized glyph is rasterized at the fractional size that makes its
  // ink span the item; scaling a native raster instead only magnifies pixels.
  // Fractional sizes travel as points and Qt maps them back through the same
  // logical DPI, so an unnormalized glyph keeps its integer pixel size.
  readonly property real logicalDpi: Screen.logicalPixelDensity > 0 ? Screen.logicalPixelDensity * 25.4 : 96
  readonly property font glyphFont: normalize
    ? Qt.font({ family: fontFamily, pointSize: renderedFontSize * normalizedScale * 72 / logicalDpi })
    : Qt.font({ family: fontFamily, pixelSize: renderedFontSize })

  // Where the rasterized ink sits by the font's account, for centering it
  // rather than the line box.
  readonly property real inkWidth: Math.max(1, metrics.tightBoundingRect.width)
  readonly property real inkHeight: Math.max(1, metrics.tightBoundingRect.height)
  readonly property real horizontalCorrection: glyph.width / 2 - (metrics.tightBoundingRect.x + inkWidth / 2)
  // Without normalization the line box stays centered so glyphs of one font
  // size keep a shared baseline; with it the ink itself is centered.
  readonly property real verticalCorrection: normalize
    ? glyph.height / 2 - (glyph.baselineOffset + metrics.tightBoundingRect.y + inkHeight / 2)
    : 0
  readonly property real baselineY: glyph.y + glyph.baselineOffset

  // Lit-pixel verification. The glyph is rendered, its pixels measured, and
  // size and position corrected until the rules hold or the passes run out.
  readonly property var hostWindow: Window.window
  readonly property real inspectScale: 4 * (Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1)
  property var inkMeasurement: null
  property var inkCompass: null
  property bool inkVerified: !normalize
  property int inkPasses: 0
  property int inkRevision: 0
  // The closest pass so far, restored if later passes only overshoot.
  property var bestPass: null
  property bool destroying: false
  readonly property var inkViolations: normalize ? IconRules.evaluate(inkCompass) : []
  // The lit box as fractions of this item: measured once the pixels are in,
  // the font's estimate until then.
  readonly property rect inkRect: inkMeasurement
    ? inkMeasurement.rect
    : Qt.rect(0.5 - tightWidth / (2 * Math.max(1, width)), 0.5 - tightHeight / (2 * Math.max(1, height)),
        tightWidth / Math.max(1, width), tightHeight / Math.max(1, height))
  readonly property real paintedCenterX: (inkRect.x + inkRect.width / 2) * width
  readonly property real paintedCenterY: (inkRect.y + inkRect.height / 2) * height

  // Everything that shapes the render, for the session cache.
  function inkKey() {
    // The reference measurement is part of what shapes the render, so it
    // belongs in the key. Without it the first fit — made from the font's
    // rough metrics before the measurement lands — is cached, and the
    // measurement arriving afterwards only ever restores that first fit.
    return [fontFamily, text, renderedFontSize, width, height, inspectScale,
      naturalAspect.toFixed(4), inkHeightRatio.toFixed(4), inkCoverage.toFixed(4)].join("|")
  }

  function applyPass(pass) {
    pixelScale = pass.pixelScale
    pixelOffsetX = pass.pixelOffsetX
    pixelOffsetY = pass.pixelOffsetY
    inkMeasurement = pass.measurement
    inkCompass = pass.compass
  }

  function probeCacheKey() {
    return "probe|" + fontFamily + "|" + text + "|" + probePixelSize
  }

  function measureProbe() {
    if (destroying || !normalize || text === "" || !hostWindow) return
    var key = probeCacheKey()
    var cached = InkCache.get(key)
    if (cached) {
      probeInk = cached
      return
    }
    var side = Math.max(1, Math.round(probeItem.width))
    probeMeasure.measure(probeItem, Qt.size(side, side), function(result) {
      if (!root || root.destroying || !result || !result.rect) return
      var w = result.rect.width * probeItem.width
      var h = result.rect.height * probeItem.height
      if (!(w > 0) || !(h > 0)) return
      var ink = { aspect: w / h, widthRatio: w / root.probePixelSize, heightRatio: h / root.probePixelSize,
        coverage: result.coverage }
      // A glyph's ink cannot be a sliver of the size it was drawn at, nor much
      // bigger than it. A measurement outside that band is a failed one, and
      // trusting it scales the glyph by the reciprocal of a near-zero number —
      // which is how one indicator ended up ballooning out of the bar. The
      // font's own metrics are the fallback; they are rough but never absurd.
      if (!(ink.heightRatio > 0.15 && ink.heightRatio < 2)
          || !(ink.widthRatio > 0.05 && ink.widthRatio < 4)) return
      InkCache.set(key, ink)
      root.probeInk = ink
    })
  }

  function requestInk() {
    inkRevision++
    inkPasses = 0
    bestPass = null
    pixelScale = 1
    pixelOffsetX = 0
    pixelOffsetY = 0
    inkMeasurement = null
    inkCompass = null
    inkVerified = !normalize
    if (!normalize) return

    var cached = InkCache.get(inkKey())
    if (cached) {
      applyPass(cached)
      inkVerified = true
      return
    }
    Qt.callLater(measureInk)
  }

  function measureInk() {
    if (destroying || !normalize || !hostWindow || width <= 0 || height <= 0 || text === "" || debugBounds) return
    var requested = inkRevision
    var key = inkKey()
    var size = Qt.size(Math.max(1, Math.round(width * inspectScale)), Math.max(1, Math.round(height * inspectScale)))
    ink.measure(root, size, function(result) {
      if (!root || root.destroying || requested !== root.inkRevision) return
      root.inkPasses++
      if (!result) {
        if (root.inkPasses < IconRules.maxPasses) Qt.callLater(root.measureInk)
        return
      }


      var compass = IconRules.compass(result, root.width, root.height)
      var pass = { pixelScale: root.pixelScale, pixelOffsetX: root.pixelOffsetX, pixelOffsetY: root.pixelOffsetY,
        measurement: result, compass: compass }
      root.inkMeasurement = result
      root.inkCompass = compass
      var best = root.bestPass ? IconRules.distance(root.bestPass.compass) : Infinity
      var reached = IconRules.distance(compass)
      if (reached < best) root.bestPass = pass

      // Run until the rules actually hold, not until a pass stops improving.
      // The correction is proportional, so a pass can overshoot and look like
      // no progress while the next one lands it — and stopping there reverts
      // to the very first placement, which is the one made before anything had
      // been measured at all. The best pass is kept regardless, so the extra
      // passes can only help; the size is already settled by the reference
      // measurement, so they are cheap.
      // The shared rule only asks that the mark reach the canvas on some axis,
      // because a drawn icon is fitted to whichever edge it meets first. A
      // glyph is held to more than that: it has to reach the block on the axis
      // it was sized for, or the row is not level. Settling for the shared
      // rule lets a glyph stop while it is still only as tall as the rough
      // estimate made before it was measured.
      var settled = IconRules.evaluate(compass).length === 0
      if (settled || root.inkPasses >= IconRules.maxPasses) {
        root.applyPass(root.bestPass)
        root.inkVerified = true
        InkCache.set(key, root.bestPass)
        return
      }

      // The reference measurement settled the size, so the passes only take
      // back the last fraction of a pixel the rasterizer shaved off the filled
      // axis, and centre the weight along the bar.
      var r = result.rect
      var filled = Math.max(r.width, r.height)
      if (filled > 0) root.pixelScale *= 1 / filled
      var shift = IconRules.balanceShift(r, result.centroid,
        IconRules.balanceAllowance(Math.min(root.width, root.height)))
      root.pixelOffsetX += shift.x * root.width
      root.pixelOffsetY += shift.y * root.height
      Qt.callLater(root.measureInk)
    })
  }

  onTextChanged: { probeInk = null; measureProbe(); requestInk() }
  onFontFamilyChanged: { probeInk = null; measureProbe(); requestInk() }
  onRenderedFontSizeChanged: requestInk()
  onProbeInkChanged: requestInk()
  onWidthChanged: requestInk()
  onHeightChanged: requestInk()
  onNormalizeChanged: requestInk()
  onHostWindowChanged: if (hostWindow) { measureProbe(); requestInk() }
  Component.onCompleted: { measureProbe(); requestInk() }
  Component.onDestruction: destroying = true

  InkMeasure {
    id: ink
  }

  InkMeasure {
    id: probeMeasure
  }

  // Never shown; only its pixels are ever read.
  Item {
    id: probeItem
    visible: false
    width: root.probePixelSize * 2
    height: root.probePixelSize * 2

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.text
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: root.probePixelSize
      renderType: Text.NativeRendering
    }
  }

  TextMetrics {
    id: baseMetrics
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    text: root.text
  }

  TextMetrics {
    id: metrics
    font: root.glyphFont
    text: root.text
  }

  Text {
    textFormat: Text.PlainText
    id: glyph
    x: (root.width - width) / 2 + root.horizontalCorrection + root.pixelOffsetX
    y: (root.height - height) / 2 + root.verticalCorrection + root.pixelOffsetY
    text: root.text
    color: root.color
    font: root.glyphFont
    renderType: Text.NativeRendering

  }

  Rectangle {
    visible: root.debugBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#4488ff"
  }

  Rectangle {
    visible: root.debugBounds
    x: 0
    y: Math.round(root.baselineY)
    width: parent.width
    height: 1
    color: "#44ff88"
  }
}
