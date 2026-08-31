import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  // Bumps whenever displayedBackground is assigned, even to an identical
  // string: a forced theme transition can re-render the same canonical path
  // in place (new SVG raster, new mtime), so the displayed resolvers must
  // re-resolve on assignment, not only on string change.
  property int displayedVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      displayedVersion += 1
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function maybeFinishTransition() {
    // Multi-monitor resolves and decodes land with real skew (a large panel's
    // cold SVG raster can trail a small one by hundreds of ms), so the shared
    // incoming/old sources are only cleared once EVERY panel's base layer has
    // settled on the final background — clearing on the first ready panel
    // would yank the slower panels back to the old wallpaper.
    if (!finishingTransition) return
    const panels = panelVariants.instances
    for (let i = 0; i < panels.length; i++) {
      if (!panels[i].baseSettled()) return
    }
    incomingBackground = ""
    oldBackground = ""
    finishingTransition = false
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.displayedVersion += 1
        root.finishingTransition = true
      }
      root.revealProgress = 1
      root.maybeFinishTransition()
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    id: panelVariants
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      // Last successful displayed resolution for this panel. It drives the
      // base layer and stands in for the old frame's fill/meta during theme
      // switches, when the old canonical handed to the transition is only a
      // snapshot copy whose directory carries no metadata.
      property string lastDisplayedCanonical: ""
      property string lastDisplayedPath: ""
      property string lastDisplayedFill: "crop"
      property color lastDisplayedFillColor: Color.background
      property real lastDisplayedFocalX: 0.5
      property real lastDisplayedFocalY: 0.5

      // Incoming source lock: each panel commits its incoming pixels/meta
      // exactly once per backgroundVersion — from its own resolver when it
      // lands in time, from the handed-down snapshot when
      // incomingFallbackTimer fires first — and never swaps them mid-reveal.
      property int incomingLockedVersion: -1
      property string incomingPath: ""
      property string incomingFill: "crop"
      property color incomingFillColor: Color.background
      property real incomingFocalX: 0.5
      property real incomingFocalY: 0.5

      function lockIncoming(path, fillMode, tint, fx, fy) {
        if (incomingLockedVersion === root.backgroundVersion) return
        incomingLockedVersion = root.backgroundVersion
        incomingFallbackTimer.stop()
        incomingPath = path
        incomingFill = fillMode
        incomingFillColor = tint
        incomingFocalX = fx
        incomingFocalY = fy
      }

      // True once this panel's base layer is painting the final background:
      // its resolver has published for the current displayed canonical and
      // the decode is no longer in flight.
      function baseSettled() {
        if (root.displayedBackground === "") return true
        if (!displayedResolver.ready || lastDisplayedCanonical !== root.displayedBackground) return false
        return base.status !== Image.Loading
      }

      function maybeStartReveal() {
        // Join tolerance: a panel whose incoming frame becomes ready after
        // the reveal's first tick still raises its mask at the current
        // spread instead of staying hidden for the rest of the animation.
        if (!root.incomingBackground || root.revealProgress >= 1 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress >= 1 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      // The snapshot fallback bound: a panel whose incoming resolve has not
      // published this long after the transition armed paints the
      // handed-down snapshot with its cached displayed meta, so one slow
      // panel never blocks or misses the shared reveal.
      Timer {
        id: incomingFallbackTimer
        interval: 250
        repeat: false
        onTriggered: {
          if (root.incomingBackground === "") return
          panel.lockIncoming(root.incomingBackground, panel.lastDisplayedFill, panel.lastDisplayedFillColor, panel.lastDisplayedFocalX, panel.lastDisplayedFocalY)
        }
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      BackgroundResolver {
        id: displayedResolver
        canonicalPath: root.displayedBackground
        screenWidth: panel.modelData.width
        screenHeight: panel.modelData.height
        refreshToken: root.displayedVersion
        onResolveVersionChanged: {
          if (ready && resolvedPath !== "") {
            panel.lastDisplayedCanonical = canonicalPath
            panel.lastDisplayedPath = resolvedPath
            panel.lastDisplayedFill = fill
            panel.lastDisplayedFillColor = fillColor
            panel.lastDisplayedFocalX = focalX
            panel.lastDisplayedFocalY = focalY
          }
          root.maybeFinishTransition()
        }
      }

      BackgroundResolver {
        id: oldResolver
        canonicalPath: root.oldBackground
        screenWidth: panel.modelData.width
        screenHeight: panel.modelData.height
        refreshToken: root.backgroundVersion
      }

      // A theme switch hands transitionBackground a snapshot copy for pixels
      // while root.currentBackground already holds the real post-swap
      // canonical, whose directory carries the variants and metadata — so the
      // incoming layer resolves against the final path and only falls back to
      // the snapshot when that resolve fails or has not landed yet.
      BackgroundResolver {
        id: incomingResolver
        canonicalPath: root.currentBackground !== "" ? root.currentBackground : root.incomingBackground
        screenWidth: panel.modelData.width
        screenHeight: panel.modelData.height
        // A forced theme transition can keep the canonical string identical
        // while re-rendering its content in place; keying on the version
        // guarantees a fresh resolve for every transition.
        refreshToken: root.backgroundVersion
        onResolveVersionChanged: {
          if (!ready || root.incomingBackground === "") return
          panel.lockIncoming(usedFallback ? root.incomingBackground : resolvedPath, fill, fillColor, focalX, focalY)
        }
      }

      WallpaperImage {
        id: base
        anchors.fill: parent
        path: panel.lastDisplayedPath
        fill: panel.lastDisplayedFill
        fillColor: panel.lastDisplayedFillColor
        focalX: panel.lastDisplayedFocalX
        focalY: panel.lastDisplayedFocalY
        asynchronous: true
        cache: true
        onStatusChanged: root.maybeFinishTransition()
      }

      WallpaperImage {
        id: oldFrame
        anchors.fill: parent
        // The old theme dir can be gone after the swap: an unchanged canonical
        // keeps this panel's displayed pixels, anything else (a snapshot) shows
        // the resolver's echo of the handed-down file.
        path: root.oldBackground === "" ? ""
          : root.oldBackground === panel.lastDisplayedCanonical ? panel.lastDisplayedPath
          : oldResolver.ready ? oldResolver.resolvedPath
          : root.oldBackground
        fill: panel.lastDisplayedFill
        fillColor: panel.lastDisplayedFillColor
        focalX: panel.lastDisplayedFocalX
        focalY: panel.lastDisplayedFocalY
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        WallpaperImage {
          id: incomingFrame
          anchors.fill: parent
          // The panel's locked incoming source: the resolver's answer when
          // it landed within incomingFallbackTimer's window, the handed-down
          // snapshot otherwise. Locking keeps the pixel source settled for
          // the whole reveal — a mid-reveal swap would blink the layer.
          path: panel.incomingPath
          fill: panel.incomingFill
          fillColor: panel.incomingFillColor
          focalX: panel.incomingFocalX
          focalY: panel.incomingFocalY
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          incomingFallbackTimer.stop()
          panel.incomingLockedVersion = -1
          panel.incomingPath = ""
          if (root.incomingBackground !== "") incomingFallbackTimer.restart()
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
