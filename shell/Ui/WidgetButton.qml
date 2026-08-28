import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons

// The button every bar item is built on. Whatever a widget hands it — a font
// glyph, a glyph beside a label, or an arbitrary icon item — the icon part is
// measured by the pixels it paints and fitted to one optical canvas, then
// verified against the shared icon rules, so items from different plugins
// and asset formats read as one even row. Plain text keeps its type metrics.
Item {
  id: root

  property var bar: null
  property string text: ""
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property real fontSize: Style.font.body
  property color foreground: bar ? bar.barForeground : Color.foreground
  property color activeColor: bar ? bar.urgent : Color.urgent
  property bool active: false
  property real horizontalMargin: 8.5
  property real verticalPadding: 6
  property real fixedWidth: -1
  property real fixedHeight: -1
  property real textRotation: 0
  property bool keepSpace: false
  property bool dimmed: false
  property bool concealed: false
  property bool interactive: true
  property bool pressable: true
  property bool useActiveColor: true
  property bool maintainIndicatorReveal: false
  property bool labelVisible: true
  // Drawn in place of text: any item, fitted to the optical canvas by the
  // pixels it renders.
  property Component iconComponent: null
  // A lone icon glyph, or one leading or trailing a label, is sized by its ink
  // to the optical canvas. A button whose glyph is a text-sized marker in a
  // run of text (the workspace dot) turns this off and keeps type metrics.
  property bool normalizeIcon: true
  // One mark, one brightness — unless the mark really is drawn in two tones.
  // A logo whose second tone covers a fair share of it is a two-tone logo and
  // is left as drawn; a sliver of one faded against the rest of its own icon
  // is an accident and is brought back to full.
  property bool flattenIcon: true
  // One square of the icon grid: the canvas an icon's ink is fitted to. One
  // size for every button, whatever font size its label happens to use; a
  // component meant to read smaller (the status indicators) declares its own.
  property real opticalSize: Style.bar.iconCanvas
  property bool debugOpticalBounds: Quickshell.env("OMARCHY_DEBUG_BAR_ICONS") === "1"
  property bool hasVisualContent: text !== "" || iconComponent !== null
  property var revealHost: bar
  property string tooltipText: ""
  property var registeredBar: null

  signal pressed(int button)
  signal wheelMoved(int delta)

  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
  }

  function hideOwnTooltip() {
    if (root.bar) root.bar.hideTooltip(root)
  }

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }

  onBarChanged: syncClickRegistration()
  onVisibleChanged: if (!visible) hideOwnTooltip()
  onInteractiveChanged: if (!interactive) hideOwnTooltip()
  onConcealedChanged: if (concealed) hideOwnTooltip()
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    destroying = true
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
  }

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real scaledHorizontalMargin: Style.spaceReal(horizontalMargin)
  readonly property real scaledVerticalPadding: Style.spaceReal(verticalPadding)
  readonly property bool tooltipHovered: visible && interactive && !concealed && mouseArea.containsMouse
  readonly property color contentColor: active && useActiveColor ? activeColor : foreground

  readonly property var iconParts: normalizeIcon && iconComponent === null ? Util.splitIconLabel(text) : null
  readonly property bool hasIconGlyph: iconParts !== null
  readonly property bool hasIcon: iconComponent !== null || hasIconGlyph
  readonly property string iconText: hasIconGlyph ? iconParts.icon : ""
  readonly property string labelText: hasIconGlyph ? iconParts.label : text
  readonly property bool iconFirst: !hasIconGlyph || iconParts.iconFirst
  // Nothing but an icon: the button takes the theme's icon slot, so plugin
  // icons space along the bar exactly like the built-in ones.
  readonly property bool iconOnly: iconComponent !== null || (hasIconGlyph && labelText === "")

  // Width of the painted label, for bar chrome that wants to line up with the
  // text rather than with the slot it sits in. Zero on icon-only buttons.
  readonly property real labelWidth: label.visible ? label.implicitWidth : 0
  // Width of everything painted: icon canvas, gap and label.
  readonly property real contentWidth: content.visible ? content.implicitWidth : 0
  // Glyph geometry, for tests and for chrome that lines up with the icon.
  readonly property real opticalCenterErrorX: glyph.visible ? glyph.paintedCenterX - opticalCanvas.width / 2 : 0
  readonly property real opticalCenterErrorY: glyph.visible ? glyph.paintedCenterY - opticalCanvas.height / 2 : 0
  readonly property real glyphPaintedWidth: glyph.visible ? glyph.inkRect.width * glyph.width : 0
  readonly property real glyphPaintedHeight: glyph.visible ? glyph.inkRect.height * glyph.height : 0
  readonly property real glyphBaselineY: glyph.visible ? glyph.baselineY : 0
  readonly property int glyphFontSize: glyph.visible ? glyph.renderedFontSize : 0
  readonly property real glyphScale: glyph.visible ? glyph.normalizedScale : 1
  // How wide the mark is against its own height, held from the first
  // measurement of the ink itself. The font's metrics are only the opening
  // guess: they disagree with what actually rasterizes, and it is the
  // rasterized ink the rules judge, so a glyph the font calls square can
  // still render half the height of the row. Held, so widening the canvas
  // below cannot feed back into it.
  readonly property real iconAspect: hasIconGlyph ? glyph.naturalAspect : 1
  // How far the mark ended up condensed; 1 is untouched.
  // How far the fit was nudged for density; 1 is untouched.
  readonly property real iconSquash: iconComponent !== null
    ? IconRules.weightFit(iconFit.inkCoverage)
    : (hasIconGlyph ? IconRules.weightFit(glyph.inkCoverage) : 1)
  // Every icon keeps one slot: a wide mark is condensed into its canvas
  // rather than handed more of the bar.
  // The room a wide mark needs to be condensed into belongs to a lone icon.
  // A glyph beside a label gets the plain block, so a labelled button is
  // exactly the width it has always been.
  // A lone icon's canvas is cut wider along the bar so the long axis of a wide
  // mark has somewhere to land. A glyph beside a label keeps the plain block,
  // so a labelled button is exactly the width it has always been — widening
  // those grows the button, and widgets size their own chrome against it.
  readonly property real opticalWidth: vertical || !iconOnly
    ? opticalSize : opticalSize * IconRules.canvasRoom
  readonly property real opticalHeight: vertical && iconOnly
    ? opticalSize * IconRules.canvasRoom : opticalSize
  readonly property real slotGrowth: 0

  readonly property bool iconInkMeasured: iconFit.measured
  // How many distinct frames an icon component has shown; more than one
  // means an animation, judged by the union of its frames.
  readonly property int iconFrames: iconFit.frameCount

  // Lit-pixel verification of what the canvas finally shows, against the
  // shared icon rules. Glyphs verify themselves as they settle; an icon
  // component is verified here once it has been fitted.
  readonly property bool inkVerified: iconComponent !== null ? iconFit.verified : (hasIconGlyph ? glyph.inkVerified : true)
  readonly property var inkCompass: iconComponent !== null ? iconFit.compass : (hasIconGlyph ? glyph.inkCompass : null)
  readonly property var inkViolations: hasIcon ? IconRules.evaluate(inkCompass) : []
  // The lit box as fractions of the optical canvas.
  readonly property rect inkRect: iconComponent !== null ? iconFit.shownRect : (hasIconGlyph ? glyph.inkRect : Qt.rect(0, 0, 1, 1))
  // What the button paints, in its own coordinates: an icon's canvas, or the
  // icon-and-label content. The bar's open-panel mark spans this end to end.
  //
  // For an icon it is the canvas, not the ink inside it. Every icon fills the
  // same canvas but reaches it with a different silhouette, so a mark drawn
  // to the ink comes out a different length under each icon — wide under the
  // wifi arc, narrow under the battery — and the row of them reads as ragged.
  // The canvas is the one extent every icon shares, so the mark is the same
  // length wherever it appears, and still exactly as wide as the icon it sits
  // under.
  readonly property real paintedX: iconOnly ? content.x + opticalCanvas.x : content.x
  readonly property real paintedY: iconOnly ? content.y + opticalCanvas.y : content.y
  readonly property real paintedWidth: iconOnly ? opticalCanvas.width : content.width
  readonly property real paintedHeight: iconOnly ? opticalCanvas.height : content.height

  readonly property var hostWindow: Window.window
  readonly property real devicePixelRatio: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  // Inspect at four times the display density so measured boxes are exact
  // well below the resolution anyone sees the icon at.
  readonly property real inspectScale: 4 * devicePixelRatio
  property bool destroying: false

  visible: hasVisualContent || keepSpace
  opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)
  implicitWidth: fixedWidth > 0 ? fixedWidth
    : (vertical ? barSize : (iconOnly ? Style.bar.iconSlot + slotGrowth : Math.max(12, content.implicitWidth + scaledHorizontalMargin * 2)))
  implicitHeight: fixedHeight > 0 ? fixedHeight
    : (vertical ? (iconOnly ? Style.bar.iconSlot + slotGrowth : Math.max(12, content.implicitHeight + scaledVerticalPadding * 2)) : barSize)

  Behavior on opacity {
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  // The label's own space glyph sets the gap between icon and text.
  TextMetrics {
    id: gapMetrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    text: " "
  }

  Row {
    id: content
    anchors.centerIn: parent
    visible: root.labelVisible || root.iconComponent !== null
    spacing: root.hasIconGlyph && root.labelText !== "" ? gapMetrics.advanceWidth : 0
    layoutDirection: root.iconFirst ? Qt.LeftToRight : Qt.RightToLeft
    rotation: root.textRotation

    Item {
      id: opticalCanvas
      anchors.verticalCenter: parent.verticalCenter
      visible: root.iconComponent !== null || (root.hasIconGlyph && root.labelVisible)
      width: root.opticalWidth
      height: root.opticalHeight

      OpticalGlyph {
        id: glyph
        anchors.fill: parent
        visible: root.iconComponent === null && root.hasIconGlyph
        text: root.iconText
        fontFamily: root.fontFamily
        fontSize: root.fontSize
        normalize: true
        color: root.contentColor
        debugBounds: root.debugOpticalBounds

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      // The icon component renders however its author drew it; its pixels are
      // then measured and the whole thing scaled about its center and shifted
      // so the ink spans and centers on the canvas. Animated icons that swap
      // image sources are measured per frame and fitted to the union, so the
      // animation keeps one steady frame of reference. The canvas is measured
      // again afterwards to verify what actually shows.
      Item {
        id: iconFit

        property rect inkRect: Qt.rect(0, 0, 1, 1)
        property point inkCentroid: Qt.point(0.5, 0.5)
        property bool measured: false
        property var measuredBoxes: ({})
        property var measuredCentroids: ({})
        property var watchedItems: []
        property int revision: 0
        property bool verified: false
        property var compass: null
        property rect shownRect: Qt.rect(0, 0, 1, 1)
        property int verifyRevision: 0
        // What each frame actually showed on the canvas. An animation is
        // fitted to the union of its frames, so it is judged by that union
        // too: the box they span together, and in each compass direction
        // the closest any frame came to the edge.
        property var shownBoxes: ({})
        property var shownCompasses: ({})
        readonly property int frameCount: Object.keys(shownBoxes).length
        // Filled across the bar, then condensed along it if the mark is wider
        // than a block, so it keeps the row's height rather than shrinking out
        // of line with it.
        // Drawn icons keep the fit they have always had: scaled evenly until
        // the ink meets whichever edge it reaches first. Filling the block the
        // way a glyph now does needs a measurement that can be trusted the
        // moment it arrives, and a component that is still drawing itself
        // reports ink far smaller than it will end up — which scales the whole
        // thing up enormously. Glyphs are measured once, on their own, so they
        // do not have that problem.
        readonly property real fitScale: inkRect.width > 0 && inkRect.height > 0
          ? Math.min(
              IconRules.meanFit(inkRect.width * width, inkRect.height * height,
                Math.min(width, height)) * IconRules.weightFit(inkCoverage),
              Math.min(1 / inkRect.width, 1 / inkRect.height))
          : 1
        readonly property real fitScaleX: fitScale
        readonly property real fitScaleY: fitScale
        property real inkCoverage: 0
        // Where the ink lands once the fit has scaled it about the center,
        // and the shift from there that brings its weight onto the canvas
        // center. Scaling answers how far the icon reaches; the shift answers
        // where it weighs, so an icon with its mass off to one side comes out
        // level with the rest of the row instead of merely boxed like it.
        readonly property rect fittedRect: Qt.rect(0.5 + (inkRect.x - 0.5) * fitScaleX,
          0.5 + (inkRect.y - 0.5) * fitScaleY, inkRect.width * fitScaleX, inkRect.height * fitScaleY)
        readonly property point fittedCentroid: Qt.point(0.5 + (inkCentroid.x - 0.5) * fitScaleX,
          0.5 + (inkCentroid.y - 0.5) * fitScaleY)
        readonly property point fitShift: IconRules.balanceShift(fittedRect, fittedCentroid,
          IconRules.balanceAllowance(Math.min(width, height)), root.vertical ? "x" : "y")

        visible: root.iconComponent !== null
        width: parent.width
        height: parent.height
        transform: Scale {
          origin.x: iconFit.width / 2
          origin.y: iconFit.height / 2
          xScale: iconFit.fitScaleX
          yScale: iconFit.fitScaleY
        }
        x: fitShift.x * width
        y: fitShift.y * height

        function imageLike(item) {
          return "source" in item && "status" in item
        }

        function collectImages(item, into) {
          if (!item) return into
          if (imageLike(item)) into.push(item)
          for (var i = 0; i < item.children.length; i++) collectImages(item.children[i], into)
          return into
        }

        // A source swap is a frame of the same icon and joins the union; a
        // part appearing, disappearing or being added is a new state of the
        // icon (a status badge, a crossed-out mark) and gets a fresh fit.
        function watchItem(item) {
          if (!item || watchedItems.indexOf(item) !== -1) return
          var list = watchedItems.slice()
          list.push(item)
          watchedItems = list
          if (imageLike(item)) {
            item.sourceChanged.connect(iconFit.requestMeasure)
            item.statusChanged.connect(iconFit.requestMeasure)
          }
          if ("visible" in item) item.visibleChanged.connect(iconFit.watch)
          if ("opacity" in item) item.opacityChanged.connect(iconFit.watch)
          if ("children" in item) item.childrenChanged.connect(iconFit.watch)
          for (var i = 0; i < item.children.length; i++) watchItem(item.children[i])
        }

        // What the mark actually paints: the visible items with nothing
        // visible inside them.
        function leaves(item, into) {
          if (!item || !item.visible) return into
          var encloses = false
          for (var i = 0; i < item.children.length; i++) {
            if (item.children[i].visible) {
              encloses = true
              leaves(item.children[i], into)
            }
          }
          if (!encloses) into.push(item)
          return into
        }

        // Weighs the faded parts of a mark against the whole of it. A second
        // tone covering a fair share of the icon is the logo being drawn in
        // two tones, and is left as its author drew it; anything less is one
        // part faded against the rest of its own icon by accident, and goes
        // back to full. A fade covering every part alike never registers,
        // which is right: that is the widget signalling a state over its
        // icon, not the icon painted in two brightnesses.
        //
        // Either way the geometry is unaffected — shape is taken before
        // brightness, so a two-tone mark measures exactly like a solid one.
        // Flattening runs before the watchers are attached, so the first pass
        // does not report itself back as a change.
        function flatten(item) {
          if (!item || !root.flattenIcon) return
          var painted = leaves(item, [])
          var total = 0, faded = 0, dim = []
          for (var i = 0; i < painted.length; i++) {
            var part = painted[i]
            var area = Math.max(0, part.width) * Math.max(0, part.height)
            total += area
            if ("opacity" in part && part.opacity > 0 && part.opacity < 1) {
              faded += area
              dim.push(part)
            }
          }
          if (total <= 0 || faded / total >= IconRules.twoToneMinShare) return
          for (var j = 0; j < dim.length; j++) dim[j].opacity = 1
        }

        function watch() {
          if (root.destroying) return
          measuredBoxes = {}
          measuredCentroids = {}
          shownBoxes = {}
          shownCompasses = {}
          measured = false
          verified = false
          compass = null
          inkRect = Qt.rect(0, 0, 1, 1)
          inkCentroid = Qt.point(0.5, 0.5)
          shownRect = Qt.rect(0, 0, 1, 1)
          flatten(iconLoader.item)
          watchItem(iconLoader.item)
          requestMeasure()
        }

        function unionOf(boxes) {
          var left = 1, top = 1, right = 0, bottom = 0, any = false
          for (var key in boxes) {
            var box = boxes[key]
            left = Math.min(left, box.x)
            top = Math.min(top, box.y)
            right = Math.max(right, box.x + box.width)
            bottom = Math.max(bottom, box.y + box.height)
            any = true
          }
          return any ? Qt.rect(left, top, right - left, bottom - top) : Qt.rect(0, 0, 1, 1)
        }

        function closestCompass(compasses) {
          var out = null
          for (var key in compasses) {
            var c = compasses[key]
            if (!c) continue
            if (!out) {
              out = {}
              for (var direction in c) out[direction] = c[direction]
              continue
            }
            for (var d in c) out[d] = d in out ? Math.min(out[d], c[d]) : c[d]
          }
          return out
        }

        function signature() {
          var images = collectImages(iconLoader.item, [])
          var parts = []
          for (var i = 0; i < images.length; i++) parts.push(String(images[i].source))
          return parts.join("\n")
        }

        function imagesSettled() {
          var images = collectImages(iconLoader.item, [])
          for (var i = 0; i < images.length; i++) {
            if (images[i].status === Image.Loading) return false
          }
          return true
        }

        function unionBox() {
          return unionOf(measuredBoxes)
        }

        // An animation is fitted to the union of its frames, so it balances
        // on where those frames weigh together rather than swaying frame by
        // frame.
        function meanCentroid(points) {
          var x = 0, y = 0, n = 0
          for (var key in points) {
            x += points[key].x
            y += points[key].y
            n++
          }
          return n > 0 ? Qt.point(x / n, y / n) : Qt.point(0.5, 0.5)
        }

        function requestMeasure() {
          revision++
          Qt.callLater(measure)
        }

        // Boxes are cached against what the icon is showing, not how big its
        // canvas is, so a canvas that grows a square has to throw them away
        // and look again. The latched aspect is kept: it is what sized the
        // canvas, and re-reading it here is how it would chase its own tail.
        function remeasureForSize() {
          if (root.destroying) return
          measuredBoxes = {}
          measuredCentroids = {}
          requestMeasure()
        }

        onWidthChanged: remeasureForSize()
        onHeightChanged: remeasureForSize()

        function measure() {
          if (root.destroying || !iconLoader.item || !root.hostWindow || width <= 0 || height <= 0) return
          if (!imagesSettled()) return
          var key = signature()
          if (key in measuredBoxes) {
            inkRect = unionBox()
            inkCentroid = meanCentroid(measuredCentroids)
            measured = true
            requestVerify()
            return
          }

          var requested = revision
          var size = Qt.size(Math.max(1, Math.round(width * root.inspectScale)), Math.max(1, Math.round(height * root.inspectScale)))
          ink.measure(iconLoader, size, function(result) {
            if (!root || root.destroying || !result) return
            // A frame that is still loading renders nothing; the status change
            // that follows measures it again.
            var boxes = iconFit.measuredBoxes
            boxes[key] = result.rect
            iconFit.measuredBoxes = boxes
            var centroids = iconFit.measuredCentroids
            centroids[key] = result.centroid
            iconFit.measuredCentroids = centroids
            iconFit.inkRect = iconFit.unionBox()
            iconFit.inkCentroid = iconFit.meanCentroid(centroids)
            if (result.coverage > 0) iconFit.inkCoverage = result.coverage
            iconFit.measured = true
            iconFit.requestVerify()
            if (requested !== iconFit.revision) Qt.callLater(iconFit.measure)
          })
        }

        function requestVerify() {
          verifyRevision++
          verified = false
          Qt.callLater(verify)
        }

        function verify() {
          if (root.destroying || !root.hostWindow || !measured || opticalCanvas.width <= 0) return
          var requested = verifyRevision
          var frame = signature()
          var size = Qt.size(Math.max(1, Math.round(opticalCanvas.width * root.inspectScale)),
            Math.max(1, Math.round(opticalCanvas.height * root.inspectScale)))
          verifyInk.measure(opticalCanvas, size, function(result) {
            if (!root || root.destroying || requested !== iconFit.verifyRevision) return
            if (result) {
              var boxes = iconFit.shownBoxes
              boxes[frame] = result.rect
              iconFit.shownBoxes = boxes
              var compasses = iconFit.shownCompasses
              compasses[frame] = IconRules.compass(result, opticalCanvas.width, opticalCanvas.height, root.vertical)
              iconFit.shownCompasses = compasses
            }
            iconFit.shownRect = iconFit.unionOf(iconFit.shownBoxes)
            iconFit.compass = iconFit.closestCompass(iconFit.shownCompasses)
            iconFit.verified = true
          })
        }

        Loader {
          id: iconLoader
          anchors.fill: parent
          sourceComponent: root.iconComponent
          onLoaded: iconFit.watch()
        }
      }

      Rectangle {
        visible: root.debugOpticalBounds
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: "#4488ff"
      }
    }

    Text {
      textFormat: Text.PlainText
      id: label
      anchors.verticalCenter: parent.verticalCenter
      visible: root.labelVisible && root.labelText !== "" && root.iconComponent === null
      text: root.labelText
      color: root.contentColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      renderType: Text.NativeRendering
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }
  }

  InkMeasure {
    id: ink
  }

  InkMeasure {
    id: verifyInk
  }

  onHostWindowChanged: if (hostWindow && iconComponent !== null) iconFit.requestMeasure()

  Rectangle {
    visible: root.debugOpticalBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#ff4455"
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: {
      if (root.bar) {
        root.bar.showTooltip(root, root.tooltipText)
      }
      if (root.maintainIndicatorReveal && root.revealHost && root.revealHost.setIndicatorItemHovered)
        root.revealHost.setIndicatorItemHovered(true)
    }
    onExited: {
      if (root.bar) {
        root.bar.hideTooltip(root)
      }
      if (root.maintainIndicatorReveal && root.revealHost && root.revealHost.setIndicatorItemHovered)
        root.revealHost.setIndicatorItemHovered(false)
    }
    onClicked: function(mouse) { if (root.pressable) root.triggerPress(mouse.button) }
    onWheel: function(wheel) { root.wheelMoved(wheel.angleDelta.y) }
  }
}
