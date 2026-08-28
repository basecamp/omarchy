import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Measures where an item's ink sits and how far it reaches. The item is
// rendered to a temporary image; ImageMagick reduces the render to the shape
// it paints, blurs that shape into one soft mass and cuts the mass at half
// its peak, then reports the box it occupies, the box of the same render
// turned 45° for the diagonals, and where its weight balances.
//
// The shape is taken before the blur, so how brightly a part was painted
// never changes where the icon is measured to be: a logo drawn in two tones
// measures the same as the same logo drawn in one. Boxes and centroids come
// back as fractions of their render, so they hold at any display size. One
// measurement runs at a time; a request made meanwhile replaces any earlier
// pending one.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  readonly property string renderPath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-shell-ink-" + Quickshell.processId
    + "-" + Date.now().toString(36) + Math.random().toString(36).slice(2) + ".png"

  property var pending: null
  property var active: null
  // A released delegate loses its QML context before it is deleted; a deferred
  // start or a grab callback landing in that window has nothing to work with.
  property bool destroying: false

  Component.onDestruction: destroying = true

  // Renders `target` at `pixelSize` and calls done(result) with
  //   rect            raw ink box as fractions of the render: how big
  //   blob            blurred mass box, or null: where the weight lies
  //   centroid        where the ink balances, as fractions of the render
  //   width, height   render size in pixels
  //   diagonal        ink box of the render turned 45°, as fractions of that
  //                   turned render, or null
  //   diagonalWidth, diagonalHeight
  // An image inked to its edges yields the full box, since there is nothing
  // to trim; a render with no ink at all, one whose ink never rises above
  // antialiasing fringe, or one that failed, yields null.
  function measure(target, pixelSize, done) {
    pending = { target: target, pixelSize: pixelSize, done: done }
    Qt.callLater(start)
  }

  function start() {
    if (destroying || active || !pending) return
    var request = pending
    pending = null
    if (!request.target) {
      request.done(null)
      return
    }

    active = request
    var grabbing = request.target.grabToImage(function(result) {
      if (root.destroying) return
      if (!result || !result.saveToFile(root.renderPath)) {
        root.finish(null)
        return
      }
      // The render is consumed in one go and removed by the same command, so
      // nothing lingers however the shell exits. Everything above the fringe
      // becomes shape before the blur, so the cut cannot depend on how opaque
      // the icon was painted; the alpha's own peak is kept from before that,
      // to tell a faint mark from an empty render. The two ramps weigh the
      // shape against a gradient across each axis, which is where it balances.
      // The blur is taken against the mark, not the frame it was rendered in,
      // so the same mark measures the same however much empty space surrounds
      // it. The raw box is reported alongside the blurred one: size comes from
      // the raw ink, position from the blurred mass.
      inspector.command = ["bash", "-c",
        'ink=$(magick "$1" -alpha extract -threshold "$2" -format "%@" info: 2>/dev/null)\n'
          + 'w=${ink%%x*}; rest=${ink#*x}; h=${rest%%+*}\n'
          + 'case $w in ""|*[!0-9]*) w=0 ;; esac; case $h in ""|*[!0-9]*) h=0 ;; esac\n'
          + 'if [ "$w" -lt 1 ] || [ "$h" -lt 1 ]; then s=1; else\n'
          + '  m=$w; [ "$h" -lt "$m" ] && m=$h\n'
          + '  s=$(awk -v m="$m" -v f="$3" \'BEGIN { v = f * m; if (v < 1) v = 1; print v }\')\n'
          + 'fi\n'
          + 'magick "$1" -alpha extract -set option:peak "%[fx:maxima]" -threshold "$2"'
          + ' -set option:shape "%[fx:mean]"'
          + ' -blur 0x"$s" -auto-level -threshold "$4" -write mpr:mask'
          + ' \\( +clone -sparse-color barycentric "0,0 black %[fx:w-1],0 white" \\) -compose multiply -composite -format "%[fx:mean] " -write info: +delete'
          + ' mpr:mask \\( +clone -sparse-color barycentric "0,0 black 0,%[fx:h-1] white" \\) -compose multiply -composite -format "%[fx:mean] " -write info: +delete'
          + ' mpr:mask \\( +clone -background black -rotate 45 -format "%w %h %@ " -write info: +delete \\)'
          + ' -format "%w %h %@ %[fx:mean] %[peak] %[shape] " info:\n'
          + 'printf "%s\\n" "$ink"\n'
          + 'rm -f -- "$1"',
        "omarchy-shell-ink", root.renderPath,
        Math.round(IconRules.fringeAlpha * 100) + "%",
        String(IconRules.opticalBlur),
        Math.round(IconRules.opticalLevel * 100) + "%"]
      inspector.running = true
    }, request.pixelSize)
    if (!grabbing) finish(null)
  }

  function finish(result) {
    var request = active
    active = null
    if (request) request.done(result)
    if (pending) Qt.callLater(start)
  }

  // One line of
  //   rampX rampY turnedW turnedH turnedBox W H box coverage peak shape rawBox
  //
  // `shape` is how much of the whole render the mark inks, taken before the
  // blur. Measured against the mark's own box that is its density — how solid
  // it looks — which is a different question from how far it reaches, and the
  // reason a slab and a hairline arc of the same size do not read the same
  // size. `rawBox` is every pixel the mark paints, which is how far it
  // reaches; the blurred box decides only where its weight lies.
  // `peak` is the alpha's highest point before the shape was taken: ink that
  // never rises above antialiasing fringe is not ink. A cut that takes
  // everything or nothing leaves an empty box, which is either an empty
  // render (coverage 0) or one inked throughout. Each ramp is the shape
  // weighed against a gradient running the length of one axis; divided by the
  // coverage it gives where the ink balances on that axis.
  function parse(text) {
    var fields = String(text || "").trim().split(/\s+/)
    if (fields.length < 10) return null

    var box = /^(\d+)x(\d+)\+(\d+)\+(\d+)$/
    var rampX = Number(fields[0]), rampY = Number(fields[1])
    var turnedWidth = Number(fields[2]), turnedHeight = Number(fields[3])
    var turned = box.exec(fields[4])
    var width = Number(fields[5]), height = Number(fields[6])
    var straight = box.exec(fields[7])
    var coverage = Number(fields[8]), peak = Number(fields[9])
    var shape = fields.length > 10 ? Number(fields[10]) : 0
    var raw = fields.length > 11 ? box.exec(fields[11]) : null

    if (!straight || !(width > 0) || !(height > 0)) return null
    if (!(peak > IconRules.fringeAlpha)) return null
    if (!(coverage > 0)) return null

    var inkWidth = Number(straight[1]), inkHeight = Number(straight[2])
    var result = {
      rect: null,
      blob: null,
      // How densely the box is inked, which is how heavy the mark reads.
      coverage: 0,
      // The ramps run black to white across w-1 pixels, so a mean read
      // against them is a fraction of that span rather than of the render.
      centroid: Qt.point(width > 1 ? (rampX / coverage) * (width - 1) / width : 0.5,
        height > 1 ? (rampY / coverage) * (height - 1) / height : 0.5),
      width: width,
      height: height,
      diagonal: null,
      diagonalWidth: 0,
      diagonalHeight: 0
    }
    if (inkWidth > 0 && inkHeight > 0) {
      result.blob = Qt.rect(Number(straight[3]) / width, Number(straight[4]) / height,
        inkWidth / width, inkHeight / height)
    }
    // Density comes from the shape, never from the blurred blob: the blob is
    // deliberately larger and softer than the mark, so measuring it reports
    // almost everything as solid. Re-based from the whole render onto the
    // mark's own box, which is the density a reader sees.
    var boxW = raw && Number(raw[1]) > 0 ? Number(raw[1]) : inkWidth
    var boxH = raw && Number(raw[2]) > 0 ? Number(raw[2]) : inkHeight
    if (shape > 0 && boxW > 0 && boxH > 0) {
      result.coverage = Math.min(1, shape * width * height / (boxW * boxH))
    }
    if (raw && Number(raw[1]) > 0 && Number(raw[2]) > 0) {
      result.rect = Qt.rect(Number(raw[3]) / width, Number(raw[4]) / height,
        Number(raw[1]) / width, Number(raw[2]) / height)
    } else if (result.blob) {
      result.rect = result.blob
    } else {
      result.rect = Qt.rect(0, 0, 1, 1)
      result.centroid = Qt.point(0.5, 0.5)
    }

    if (turned && turnedWidth > 0 && turnedHeight > 0) {
      var turnedInkWidth = Number(turned[1]), turnedInkHeight = Number(turned[2])
      if (turnedInkWidth > 0 && turnedInkHeight > 0) {
        result.diagonal = Qt.rect(Number(turned[3]) / turnedWidth, Number(turned[4]) / turnedHeight,
          turnedInkWidth / turnedWidth, turnedInkHeight / turnedHeight)
        result.diagonalWidth = turnedWidth
        result.diagonalHeight = turnedHeight
      }
    }
    return result
  }

  Process {
    id: inspector
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.destroying) root.finish(root.parse(text))
    }

    onExited: if (!root.destroying && root.active) root.finish(null)
  }
}
