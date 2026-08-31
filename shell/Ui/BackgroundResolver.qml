import QtQuick
import Quickshell.Io
import qs.Commons

// Non-visual helper: resolves a background's per-screen variant and render
// metadata through omarchy-theme-bg-resolve. Every failure path publishes the
// canonical path with today's defaults (crop, centered, theme background), so
// a missing resolver or malformed output can never blank a wallpaper layer.
Item {
  id: root

  property string canonicalPath: ""
  property int screenWidth: 0
  property int screenHeight: 0
  // Consumers bump this to force a re-resolve when the inputs are
  // string-identical but the underlying content may have changed (a forced
  // theme transition re-renders the same canonical path in place, giving a
  // new mtime and thus a new raster cache key).
  property int refreshToken: 0

  property string resolvedPath: ""
  property string fill: "crop"
  property color fillColor: Color.background
  property real focalX: 0.5
  property real focalY: 0.5
  // True once the current inputs have a published resolution (a fallback
  // counts: it means the resolution settled, not that an image exists).
  property bool ready: false
  // True when the last publish came from the fallback path rather than a
  // successful resolve; consumers holding a safer pixel source (a transition
  // snapshot) can prefer it over the canonical echo.
  property bool usedFallback: false
  // Bumps on every publish so consumers can react to a re-resolution even
  // when it lands on the same values.
  property int resolveVersion: 0

  property int requestSeq: 0
  property bool resolvePending: false

  visible: false

  onCanonicalPathChanged: requestResolve()
  onScreenWidthChanged: requestResolve()
  onScreenHeightChanged: requestResolve()
  onRefreshTokenChanged: requestResolve()
  Component.onCompleted: requestResolve()

  function requestResolve() {
    requestSeq += 1
    ready = false
    if (!canonicalPath || screenWidth <= 0 || screenHeight <= 0) {
      // Also drop any queued relaunch: a resolve spawned for the now-invalid
      // inputs would run with an empty --canonical, which silently resolves
      // the current background link instead of failing.
      resolvePending = false
      publishFallback(requestSeq)
      return
    }
    if (resolveProc.running) {
      resolvePending = true
      return
    }
    startResolve()
  }

  function startResolve() {
    resolvePending = false
    // Re-validate: inputs can go invalid between queueing and a relaunch.
    if (!canonicalPath || screenWidth <= 0 || screenHeight <= 0) {
      publishFallback(requestSeq)
      return
    }
    resolveProc.seq = requestSeq
    resolveProc.command = [
      "omarchy-theme-bg-resolve",
      "--screen", screenWidth + "x" + screenHeight,
      "--canonical", canonicalPath
    ]
    resolveProc.running = true
  }

  function publishFallback(seq) {
    if (seq !== requestSeq) return
    resolvedPath = canonicalPath
    fill = "crop"
    fillColor = Color.background
    focalX = 0.5
    focalY = 0.5
    usedFallback = true
    ready = true
    resolveVersion += 1
  }

  function publishResult(seq, raw) {
    if (seq !== requestSeq) return
    var meta = null
    try {
      meta = JSON.parse(raw)
    } catch (error) {
      meta = null
    }
    if (!meta || typeof meta.path !== "string" || meta.path.length === 0) {
      publishFallback(seq)
      return
    }
    resolvedPath = meta.path
    fill = ["crop", "fit", "center", "tile"].indexOf(meta.fill) >= 0 ? meta.fill : "crop"
    fillColor = /^#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$/.test(String(meta.fill_color)) ? meta.fill_color : Color.background
    focalX = isFinite(Number(meta.focal_x)) ? Util.clamp(meta.focal_x, 0, 1) : 0.5
    focalY = isFinite(Number(meta.focal_y)) ? Util.clamp(meta.focal_y, 0, 1) : 0.5
    usedFallback = false
    ready = true
    resolveVersion += 1
  }

  Process {
    id: resolveProc

    stdout: StdioCollector { id: resolveStdout; waitForEnd: true }

    property int seq: 0

    onExited: function(exitCode) {
      // Inputs changed while the resolve ran: its answer is stale either way.
      if (root.resolvePending) {
        root.startResolve()
        return
      }
      if (exitCode === 0) root.publishResult(resolveProc.seq, String(resolveStdout.text || "").trim())
      else root.publishFallback(resolveProc.seq)
    }
  }
}
