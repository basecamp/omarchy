import QtQuick
import Quickshell.Io
import qs.Commons

// Animated branding drawn on the lock surface itself. The session lock renders
// above every window, so the windowed screensaver can never show through it --
// anything visible while locked has to be painted here.
//
// Deliberately input-transparent: it declares no MouseArea and takes no focus,
// so the password field behind it keeps receiving every keystroke.
Item {
  id: root

  property string brandingPath: ""

  // Drives one cycle: 0 hidden, 1 fully drawn.
  property real phase: 0
  property int effect: 0
  property color inkColor: Color.foreground
  property string displayText: ""
  // Position is stored as a 0..1 fraction of the free space rather than in
  // pixels, so it is resolved against the block's current size. Pixels picked
  // before the text had measured itself put the logo partly off-screen.
  property real posFx: 0.5
  property real posFy: 0.5

  readonly property string logoText: {
    var raw = brandingFile.loaded ? String(brandingFile.text() || "") : ""
    // A trailing newline adds a blank row and skews the vertical centring.
    return raw.replace(/\s+$/, "") || "omarchy"
  }
  readonly property var logoLines: logoText.split("\n")
  readonly property int logoRows: Math.max(1, logoLines.length)
  readonly property int logoCols: {
    var widest = 0
    for (var i = 0; i < logoLines.length; i++) widest = Math.max(widest, logoLines[i].length)
    return Math.max(1, widest)
  }

  // Advance width per pixel of font size, measured rather than assumed.
  readonly property real glyphRatio: glyphMetrics.advanceWidth > 0 ? glyphMetrics.advanceWidth / 100 : 0.6
  // Constrained on both axes so tall art on a short screen still fits.
  readonly property int glyphSize: {
    var byWidth = (width * 0.5) / logoCols / Math.max(0.1, glyphRatio)
    var byHeight = (height * 0.5) / logoRows
    return Math.max(6, Math.floor(Math.min(byWidth, byHeight)))
  }

  readonly property real marginX: Math.max(40, width * 0.06)
  readonly property real marginY: Math.max(40, height * 0.08)
  readonly property var palette: [Color.foreground, Color.accent, Color.lock.borderActive, Color.muted]

  function pickCycle() {
    effect = Math.floor(Math.random() * 3)
    inkColor = palette[Math.floor(Math.random() * palette.length)]
    posFx = Math.random()
    posFy = Math.random()
    displayText = logoText
  }

  // Randomised glyphs settling into the real art, left to right.
  function scrambled(source, progress) {
    var pool = "▀▄█▌▐░▒▓/\\|_-=+*#"
    var cut = Math.floor(source.length * progress)
    var out = ""

    for (var i = 0; i < source.length; i++) {
      var c = source.charAt(i)
      if (c === "\n" || c === " " || i < cut) out += c
      else out += pool.charAt(Math.floor(Math.random() * pool.length))
    }

    return out
  }

  Component.onCompleted: pickCycle()

  FileView {
    id: brandingFile
    path: root.brandingPath
    watchChanges: true
    printErrors: false
  }

  TextMetrics {
    id: glyphMetrics
    font.family: "monospace"
    font.pixelSize: 100
    text: "M"
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  Item {
    id: block
    width: logo.implicitWidth
    height: logo.implicitHeight

    // Slow wander on top of the per-cycle jump, so a held frame is never
    // perfectly static on the panel.
    property real driftX: 0
    property real driftY: 0

    // No Behavior on these: the block only moves while phase is 0, which is
    // while it is invisible, so there is nothing to glide.
    x: root.marginX + root.posFx * Math.max(0, root.width - width - root.marginX * 2) + driftX
    y: root.marginY + root.posFy * Math.max(0, root.height - height - root.marginY * 2) + driftY

    opacity: root.effect === 1 ? 1 : root.phase
    scale: root.effect === 0 ? 0.94 + 0.06 * root.phase : 1

    Text {
      id: logo
      // A single Text keeps the block art aligned; the effects act on the
      // string or on the whole block, never on per-character items.
      text: {
        if (root.effect === 1) return root.logoText.substring(0, Math.ceil(root.logoText.length * root.phase))
        if (root.effect === 2) return root.displayText
        return root.logoText
      }
      font.family: "monospace"
      font.pixelSize: root.glyphSize
      color: root.inkColor
      textFormat: Text.PlainText
      lineHeight: 1.0
      lineHeightMode: Text.ProportionalHeight
      renderType: Text.NativeRendering
    }
  }

  SequentialAnimation {
    running: root.visible
    loops: Animation.Infinite

    ScriptAction { script: root.pickCycle() }
    NumberAnimation { target: root; property: "phase"; from: 0; to: 1; duration: 2600; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 9000 }
    NumberAnimation { target: root; property: "phase"; from: 1; to: 0; duration: 1100; easing.type: Easing.InCubic }
    PauseAnimation { duration: 500 }
  }

  SequentialAnimation {
    running: root.visible
    loops: Animation.Infinite
    ParallelAnimation {
      NumberAnimation { target: block; property: "driftX"; to: 18; duration: 7000; easing.type: Easing.InOutSine }
      NumberAnimation { target: block; property: "driftY"; to: -12; duration: 9000; easing.type: Easing.InOutSine }
    }
    ParallelAnimation {
      NumberAnimation { target: block; property: "driftX"; to: -18; duration: 8000; easing.type: Easing.InOutSine }
      NumberAnimation { target: block; property: "driftY"; to: 12; duration: 6000; easing.type: Easing.InOutSine }
    }
  }

  Timer {
    // Only ticks while a scramble is resolving.
    running: root.visible && root.effect === 2 && root.phase < 1
    interval: 55
    repeat: true
    onTriggered: root.displayText = root.scrambled(root.logoText, root.phase)
  }
}
