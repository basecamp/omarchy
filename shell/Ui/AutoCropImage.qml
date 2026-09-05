import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Quickshell
import qs.Commons

// Fits an image by the pixels it actually paints. The source is rendered off
// to the side, its alpha channel is measured for the exact box of lit pixels,
// and the visible image is scaled and shifted so that box fills and centers
// this item. Nominal dimensions and baked-in transparent padding stop
// mattering; only the ink does. What finally shows is measured once more and
// checked against the shared icon rules.
Item {
  id: root

  property url source
  property bool colorized: false
  property color color: Color.foreground

  // Ink bounds as fractions of the rendered image box, so they hold at any
  // display size. The full box until a measurement lands, or when the image
  // is lit to its edges and there is nothing to trim.
  property rect inkRect: Qt.rect(0, 0, 1, 1)
  property bool measured: false
  // Verification of the fitted result.
  property bool inkVerified: false
  property var inkCompass: null
  readonly property var inkViolations: IconRules.evaluate(inkCompass)

  readonly property real fitScale: inkRect.width > 0 && inkRect.height > 0
    ? Math.min(width, height) / Math.max(inkRect.width * width, inkRect.height * height)
    : 1
  readonly property var hostWindow: Window.window
  readonly property real devicePixelRatio: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  // Inspect at four times the display density so the box is exact well below
  // the resolution anyone sees the icon at.
  readonly property real inspectScale: 4 * devicePixelRatio

  property int revision: 0
  property int verifyRevision: 0
  // A released delegate loses its QML context before it is deleted, and a
  // deferred inspection landing in that window cannot grab anything.
  property bool destroying: false

  clip: true

  function requestInspection() {
    revision++
    measured = false
    inkVerified = false
    Qt.callLater(inspect)
  }

  function inspect() {
    if (destroying || String(source) === "" || width <= 0 || height <= 0) return
    if (!hostWindow || probe.status !== Image.Ready) return

    var requested = revision
    var size = Qt.size(Math.max(1, Math.round(width * inspectScale)), Math.max(1, Math.round(height * inspectScale)))
    ink.measure(probe, size, function(result) {
      if (!root || root.destroying || requested !== root.revision) return
      root.inkRect = result ? result.rect : Qt.rect(0, 0, 1, 1)
      root.measured = true
      root.requestVerify()
    })
  }

  function requestVerify() {
    verifyRevision++
    inkVerified = false
    Qt.callLater(verify)
  }

  function verify() {
    if (destroying || !hostWindow || !measured || width <= 0 || height <= 0) return
    var requested = verifyRevision
    var size = Qt.size(Math.max(1, Math.round(width * inspectScale)), Math.max(1, Math.round(height * inspectScale)))
    verifyInk.measure(root, size, function(result) {
      if (!root || root.destroying || requested !== root.verifyRevision) return
      root.inkCompass = result ? IconRules.compass(result, root.width, root.height) : null
      root.inkVerified = true
    })
  }

  onSourceChanged: requestInspection()
  onHostWindowChanged: if (hostWindow) requestInspection()
  Component.onDestruction: destroying = true

  InkMeasure {
    id: ink
  }

  InkMeasure {
    id: verifyInk
  }

  // Rendered at inspection density for measuring only; parked outside the
  // clipped bounds so it never shows.
  Image {
    id: probe
    x: -root.width * 2 - 1
    width: root.width
    height: root.height
    source: root.source
    cache: false
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.max(1, Math.round(width * root.inspectScale))
    sourceSize.height: Math.max(1, Math.round(height * root.inspectScale))
    onStatusChanged: if (status === Image.Ready) root.requestInspection()
  }

  // The visible image shares the probe's box proportions and source size, so
  // it shows the very pixmap that was measured (icon themes hand out
  // differently padded rasters per requested size) and the fractions map
  // straight onto it: scale until the ink spans the item, then shift so the
  // ink's center sits on the item's center.
  Image {
    id: display
    width: root.width * root.fitScale
    height: root.height * root.fitScale
    x: root.width / 2 - (root.inkRect.x + root.inkRect.width / 2) * width
    y: root.height / 2 - (root.inkRect.y + root.inkRect.height / 2) * height
    source: root.source
    cache: false
    fillMode: Image.PreserveAspectFit
    mipmap: true
    sourceSize.width: probe.sourceSize.width
    sourceSize.height: probe.sourceSize.height
    // Kept as a hidden layer so the effect can sample it as a texture.
    visible: !root.colorized
    layer.enabled: root.colorized
  }

  MultiEffect {
    anchors.fill: display
    source: display
    visible: root.colorized
    colorization: 1.0
    colorizationColor: root.color
  }
}
