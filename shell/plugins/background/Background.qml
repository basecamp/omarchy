import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "StartupBackgroundModel.js" as StartupBackgroundModel

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
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  // Injected by the first-party service loader. Startup playback ends rather
  // than pausing when the desktop is covered, so it never resumes unexpectedly
  // after a lock or screensaver.
  property var shell: null
  readonly property var lockService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.lock") : null
  readonly property var idleService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property bool lockActive: lockService ? lockService.locked : false
  readonly property bool screensaverActive: idleService ? idleService.screensaverWindowCount > 0 : false
  readonly property bool sessionObscured: lockActive || screensaverActive

  readonly property string runtimeDirectory: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property string hyprlandSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
  readonly property string startupSessionClaimPath: StartupBackgroundModel.sessionClaimPath(runtimeDirectory, hyprlandSignature)
  property bool startupPrepared: false
  property bool startupCancelled: false
  property bool startupActive: false
  property int startupScreenWaitAttempts: 0
  property string startupBackgroundPath: ""
  property string startupCandidateVideoPath: ""
  property string startupCandidateFirstFramePath: ""
  property string startupVideoPath: ""
  property string startupFirstFramePath: ""
  property var startupPendingScreens: []

  onSessionObscuredChanged: if (sessionObscured && startupPrepared) cancelStartup()

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function screenNames() {
    var screens = Quickshell.screens || []
    var names = []

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      var name = screen ? String(screen.name || "") : ""
      if (name && screen.width > 0 && screen.height > 0 && names.indexOf(name) === -1) names.push(name)
    }

    return names
  }

  function prepareStartup(backgroundPath) {
    backgroundPath = String(backgroundPath || "").trim()
    if (startupPrepared || !backgroundPath) return

    startupPrepared = true
    startupBackgroundPath = backgroundPath

    var assets = StartupBackgroundModel.assetsForBackground(backgroundPath)
    startupCandidateVideoPath = assets.videoPath
    startupCandidateFirstFramePath = assets.firstFramePath

    if (!startupCandidateVideoPath || !startupSessionClaimPath || sessionObscured) {
      cancelStartup()
      return
    }

    startupVideoProbe.running = true
  }

  function waitForStartupScreens() {
    if (startupCancelled || currentBackground !== startupBackgroundPath || sessionObscured) {
      cancelStartup()
      return
    }

    var names = screenNames()
    if (names.length === 0) {
      startupScreenWaitAttempts += 1
      if (startupScreenWaitAttempts < 50) startupScreenWaitTimer.restart()
      else cancelStartup()
      return
    }

    startupPendingScreens = names
    startupClaimProc.running = true
  }

  function startupPendingFor(screenName) {
    return startupPendingScreens.indexOf(String(screenName || "")) !== -1
  }

  function finishStartupScreen(screenName) {
    screenName = String(screenName || "")
    if (!startupActive || !startupPendingFor(screenName)) return

    var pending = []
    for (var i = 0; i < startupPendingScreens.length; i++) {
      if (startupPendingScreens[i] !== screenName) pending.push(startupPendingScreens[i])
    }
    startupPendingScreens = pending
    if (pending.length === 0) cancelStartup()
  }

  function cancelStartup() {
    startupCancelled = true
    startupActive = false
    startupPendingScreens = []
    startupVideoPath = ""
    startupFirstFramePath = ""
    startupScreenWaitTimer.stop()
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    if (startupPrepared && finalPath !== startupBackgroundPath) cancelStartup()
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
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
      onStreamFinished: {
        var path = String(text || "").trim()
        root.setBackground(path, false)
        root.prepareStartup(path)
      }
    }
  }

  Process {
    id: startupVideoProbe
    command: ["test", "-f", root.startupCandidateVideoPath]
    onExited: function(exitCode) {
      if (root.startupCancelled) return
      if (exitCode === 0) startupFirstFrameProbe.running = true
      else root.cancelStartup()
    }
  }

  Process {
    id: startupFirstFrameProbe
    command: ["test", "-f", root.startupCandidateFirstFramePath]
    onExited: function(exitCode) {
      if (root.startupCancelled) return
      root.startupFirstFramePath = exitCode === 0 ? root.startupCandidateFirstFramePath : ""
      root.waitForStartupScreens()
    }
  }

  Process {
    id: startupClaimProc
    command: ["mkdir", root.startupSessionClaimPath]
    onExited: function(exitCode) {
      if (root.startupCancelled) return
      if (exitCode !== 0 || root.currentBackground !== root.startupBackgroundPath || root.sessionObscured) {
        root.cancelStartup()
        return
      }

      root.startupVideoPath = root.startupCandidateVideoPath
      root.startupActive = true
    }
  }

  Timer {
    id: startupScreenWaitTimer
    interval: 100
    repeat: false
    onTriggered: root.waitForStartupScreens()
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
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
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
      // leaving a black desktop until omarchy-shell is restarted. The startup
      // player unloads after its short run, so correctness wins over parking
      // the layer while the permanent wallpaper is static.
      updatesEnabled: true

      readonly property bool fullscreenHere: ToplevelManager.activeToplevel
        && ToplevelManager.activeToplevel.fullscreen
        && !!Hyprland.focusedMonitor
        && String(Hyprland.focusedMonitor.name || "") === String(modelData.name || "")
      property bool maskReady: false

      Component.onDestruction: root.finishStartupScreen(String(modelData.name || ""))

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: base
        anchors.fill: parent
        source: root.imageUrl(root.displayedBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        fillMode: Image.PreserveAspectCrop
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

        Image {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(root.incomingBackground)
          fillMode: Image.PreserveAspectCrop
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

      StartupBackgroundVideo {
        anchors.fill: parent
        active: root.startupActive && root.startupPendingFor(String(panel.modelData.name || ""))
        obscured: panel.fullscreenHere
        videoPath: root.startupVideoPath
        firstFramePath: root.startupFirstFramePath
        onPlaybackComplete: root.finishStartupScreen(String(panel.modelData.name || ""))
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
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
