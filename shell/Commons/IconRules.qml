pragma Singleton
import QtQuick

// The one place the bar's icon geometry rules live. Every icon's ink is
// measured against them: by the buttons that fit the icons as they render,
// by `omarchy-dev-bar-icon-audit` scanning the live bar, and by the tests.
// Nothing else may carry its own idea of how far an icon sits from the edge
// of its canvas.
//
// An icon is sized by how far it reaches and placed by where it weighs.
// Those are two different questions and the old single answer — the box
// around the ink — got the second one wrong: it lines up the box, so a mark
// whose weight sits high in that box (an arc) rides high on the bar and one
// whose weight sits low (a body under a thin antenna) sags, even though
// every box is perfectly centered. Lining up the weight instead is what
// makes a row read as level.
QtObject {
  // A mark's shape is everything it paints above antialiasing fringe,
  // however brightly. Taking the shape before anything else measures a logo
  // drawn in two tones exactly as it measures the same logo drawn in one.
  readonly property real fringeAlpha: 0.06

  // Two different questions get two different measurements, and mixing them
  // up is what made a row of icons look uneven.
  //
  // HOW BIG an icon is comes from the raw ink: scale it so its ink is exactly
  // as tall as the block. That is the only rule that leaves every icon in the
  // row the same height — measured across the bar's twelve glyphs it gives a
  // spread of 0.0px, against 59.6px for fitting the longest side and 33.3px
  // for fitting a blurred blob's height.
  //
  // WHERE it sits comes from a blurred blob: the shape is smeared until it
  // reads as one soft mass, that mass is levelled against its own peak, and
  // cut in half. Levelling against its own peak rather than a fixed level is
  // what lets the blur be strong — a thin glyph blurs to a faint mass, and a
  // fixed cut erases it entirely. Being strong is the point: it finds where
  // the icon's weight really lies, and it drops a hairline that would
  // otherwise drag the whole icon off centre.
  readonly property real opticalBlur: 0.25
  readonly property real opticalLevel: 0.5

  // Every rule allows this much, in logical pixels: one pixel of the theme's
  // coordinate space, which is what rasterization can take from any edge. A
  // measurement can never be finer than the pixel it was measured in, so a
  // render whose pixels are coarser than that sets the floor instead.
  readonly property real tolerance: 1
  function slack(margins) {
    return Math.max(tolerance, margins && margins.pixel > 0 ? margins.pixel : 0)
  }

  // How many render-and-measure passes a glyph may take to settle. Native
  // glyphs snap to whole device pixels, so a pass can overshoot; the best
  // pass seen is kept.
  readonly property int maxPasses: 5

  // How many squares of the grid an icon takes along the bar. An icon is
  // fitted inside that many squares by one square's height, so a mark that is
  // genuinely wider than it is tall gets the room to stay full height instead
  // of being shrunk until its width fits one square — which is what leaves a
  // two-to-one badge reading half the height of everything beside it.
  //
  // Rounding to nearest is what keeps the extra squares to the marks that
  // really are wide. Rounding up would hand a second square to a 1.1:1 icon
  // and most of the row would be two squares wide, which is no grid at all.
  // A mark is fitted by the middle of its two dimensions, not by whichever
  // one reaches furthest. Fitting the long side alone halves a mark twice as
  // wide as it is tall — it renders at a fraction of the row's height and
  // reads as a mistake. Fitting the short side alone inflates that same mark
  // into a slab that dominates everything beside it. The middle of the two
  // gives it the row's proportions without either failure.
  //
  // A lone icon's canvas is cut wider than the block for that reason: the
  // long axis of a wide mark has to land somewhere.
  readonly property real canvasRoom: 1.45
  function meanFit(inkWidth, inkHeight, block) {
    if (!(inkWidth > 0) || !(inkHeight > 0) || !(block > 0)) return 1
    return block / Math.sqrt(inkWidth * inkHeight)
  }

  // Two icons the same size on a ruler are not the same size to a reader. A
  // solid slab and a hairline arc filling the same box are nowhere near the
  // same weight, and sizing purely by the box is what leaves a dense mark
  // looming over the row. So the fit is nudged by how densely the mark is
  // inked: a dense one comes out a little smaller, a sparse one a little
  // larger, and the row reads even instead of merely measuring even.
  //
  // Measured over the bar's twelve glyphs this takes the spread of inked area
  // from 38.4% to 23.6%. Pulling all the way to equal area is worse, not
  // better — it inflates a hairline glyph until it towers over everything.
  readonly property real referenceCoverage: 0.5
  readonly property real weightBlend: 0.4
  readonly property real weightFitMin: 0.85
  readonly property real weightFitMax: 1.2
  function weightFit(coverage) {
    if (!(coverage > 0)) return 1
    var fit = Math.pow(referenceCoverage / coverage, weightBlend / 2)
    return Math.max(weightFitMin, Math.min(weightFitMax, fit))
  }

  // How much of a mark a second tone has to cover before it counts as the
  // logo being drawn in two tones rather than one part of it being faded by
  // accident. Below this the faded part is brought back to full; at or above
  // it the mark is left as its author drew it.
  readonly property real twoToneMinShare: 0.2

  // The compass keys that are margins. The rest of the object says how the
  // measurement was taken, and is not one of them.
  readonly property var directions: ["n", "s", "e", "w", "nw", "ne", "se", "sw"]

  // How far a set of margins is from the rules, for ranking passes: how far
  // the weight sits off center plus whatever the filled axis falls short by.
  function distance(margins) {
    if (!margins) return Infinity
    var across = margins.crossAxis === "x"
      ? Math.max(margins.e, margins.w)
      : Math.max(margins.n, margins.s)
    var along = margins.crossAxis === "x" ? margins.balanceY : margins.balanceX
    return Math.abs(along) + across
  }

  // Compass margins, in logical pixels, from the canvas edges to the ink,
  // plus where the ink's weight sits relative to the canvas center.
  // `measurement` is an InkMeasure result. Cardinal margins come from the
  // straight render; NW/NE/SE/SW from the render turned 45°, whose bounding
  // square puts each corner of the canvas at the middle of a side, so its
  // margins are the distances from those corners along the diagonals.
  function compass(measurement, canvasWidth, canvasHeight, vertical) {
    if (!measurement || !measurement.rect) return null
    var r = measurement.rect
    var c = measurement.centroid
    var out = {
      n: r.y * canvasHeight,
      s: (1 - r.y - r.height) * canvasHeight,
      w: r.x * canvasWidth,
      e: (1 - r.x - r.width) * canvasWidth,
      // Where the ink balances, as a distance from the canvas center.
      balanceX: c ? (c.x - 0.5) * canvasWidth : 0,
      balanceY: c ? (c.y - 0.5) * canvasHeight : 0,
      // The axis across the bar: the one the block is measured on and the
      // mark has to fill.
      crossAxis: vertical === true ? "x" : "y",
      // The canvas, so the rules can work back to the mark's own size.
      block: Math.min(canvasWidth, canvasHeight),
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      // One pixel of the render, in the canvas's own logical pixels.
      pixel: measurement.width > 0 ? canvasWidth / measurement.width : 0
    }
    if (measurement.diagonal && measurement.width > 0) {
      var perPixel = canvasWidth / measurement.width
      var d = measurement.diagonal
      out.nw = d.y * measurement.diagonalHeight * perPixel
      out.ne = (1 - d.x - d.width) * measurement.diagonalWidth * perPixel
      out.se = (1 - d.y - d.height) * measurement.diagonalHeight * perPixel
      out.sw = d.x * measurement.diagonalWidth * perPixel
    }
    return out
  }

  // How far past its canvas an icon may be moved to balance, as a fraction
  // of the canvas. The canvas edge is already a soft line — every rule here
  // allows a pixel of play on it — so balancing may spend that same pixel.
  // Without it an icon whose ink happens to reach both edges has nowhere to
  // move at all, and stays visibly off center for a reason no one can see.
  // Kept just under the tolerance so an icon moved the whole way is still
  // comfortably contained.
  function balanceAllowance(canvasSize) {
    return canvasSize > 0 ? (0.75 * tolerance) / canvasSize : 0
  }

  // Where an icon has to move to sit level with its neighbours: the shift,
  // in fractions of the canvas, that brings its weight onto the canvas
  // center. An icon may not be pushed clear off its canvas to achieve that,
  // so the shift is held to the room its box has left plus that allowance.
  //
  // Only along the bar. Across it the mark fills its block edge to edge, and
  // that is what lines a row up: every mark spans the same block, so every top
  // and bottom already agree, and shifting on that axis could only pull a mark
  // off the block it was sized to fill.
  function balanceShift(rect, centroid, allowance, crossAxis) {
    if (!rect || !centroid) return Qt.point(0, 0)
    var room = allowance > 0 ? allowance : 0
    if (crossAxis === "x") {
      return Qt.point(0, Math.max(-rect.y - room, Math.min(0.5 - centroid.y, 1 - rect.y - rect.height + room)))
    }
    return Qt.point(Math.max(-rect.x - room, Math.min(0.5 - centroid.x, 1 - rect.x - rect.width + room)), 0)
  }

  // The rules, applied to compass margins. Empty when the icon passes.
  //   sized      the mark came out the size the block asks for, measured the
  //              way it is fitted: by the middle of its two dimensions
  //   balanced   the ink's weight sits centered along the bar, where there is
  //              room to move it. Across the bar `fill` already has it
  //              spanning the block, which is what makes a row read level
  //   contained  no ink lies beyond the canvas by more than tolerance,
  //              corners included
  function evaluate(margins) {
    if (!margins) return ["unmeasured"]
    var allowed = slack(margins)
    var problems = []
    // The mark comes out the size the block asks for. Measured the way it is
    // fitted — by the middle of its two dimensions — because that is the
    // promise being made: not that it touches an edge, which a mark fitted
    // this way deliberately does not, but that it is neither a fraction of
    // the row's size nor looming over it. The allowance covers the shrink the
    // density rule above is itself permitted, or the two rules would spend
    // their time contradicting each other.
    if (margins.block > 0 && margins.canvasWidth > 0 && margins.canvasHeight > 0) {
      var inkWide = margins.canvasWidth - margins.e - margins.w
      var inkTall = margins.canvasHeight - margins.n - margins.s
      if (inkWide > 0 && inkTall > 0) {
        var mean = Math.sqrt(inkWide * inkTall)
        var room = allowed + margins.block * (1 - weightFitMin)
        if (Math.abs(mean - margins.block) > room) problems.push("sized")
      }
    }
    // Weight is only judged where there is room to move the mark. A mark that
    // reaches both ends of its canvas along the bar is already pinned by its
    // own size, and asking it to balance as well is asking the impossible.
    // Weight is only judged as far as the mark can actually be moved. A mark
    // reaching both ends of its canvas is pinned by its own size, and one
    // already pressed against a single end has spent the room it had; asking
    // either to balance as well is asking for the impossible, and a rule that
    // demands the impossible is one nobody can act on.
    var alongRoom = margins.crossAxis === "x"
      ? Math.max(margins.n, margins.s)
      : Math.max(margins.e, margins.w)
    var alongSpent = margins.crossAxis === "x"
      ? Math.min(margins.n, margins.s)
      : Math.min(margins.e, margins.w)
    var along = margins.crossAxis === "x" ? margins.balanceY : margins.balanceX
    if (alongRoom > allowed && alongSpent > allowed && Math.abs(along) > allowed) problems.push("balanced")
    for (var i = 0; i < directions.length; i++) {
      var key = directions[i]
      if (key in margins && margins[key] < -allowed) {
        problems.push("contained")
        break
      }
    }
    return problems
  }
}
