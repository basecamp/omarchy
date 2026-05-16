import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string currentBackgroundLink: home + "/.config/omarchy/current/background"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property real revealProgress: 1

  function imageUrl(path) {
    if (!path) return ""
    return "file://" + path
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path) {
    path = String(path || "").trim()
    if (!path || path === currentBackground) return
    currentBackground = path
    backgroundVersion += 1

    if (!displayedBackground) {
      displayedBackground = path
      revealProgress = 1
      return
    }

    revealAnimation.stop()
    finishingTransition = false
    oldBackground = displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-lc", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-lc", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim())
    }
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: root.refreshBackground()
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
        root.displayedBackground = root.incomingBackground
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
      visible: true
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      property bool maskReady: false
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
        cache: false
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      Image {
        id: incomingFrame
        anchors.fill: parent
        source: root.imageUrl(root.incomingBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: root.incomingBackground !== "" && status === Image.Ready
        opacity: root.revealProgress >= 1 ? 1 : 0.001
        onStatusChanged: if (status === Image.Ready && root.incomingBackground) revealCanvas.prepareImage()
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: if (status === Image.Ready && root.incomingBackground) revealCanvas.requestPaint()
      }

      Canvas {
        id: revealCanvas
        anchors.fill: parent
        visible: root.incomingBackground !== "" && root.revealProgress < 1 && incomingFrame.status === Image.Ready && oldFrame.status === Image.Ready
        opacity: panel.maskReady ? 1 : 0
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Immediate

        readonly property real slant: -0.18

        function prepareImage() {
          var src = root.imageUrl(root.incomingBackground)
          if (!src) return
          if (isImageLoaded(src)) {
            requestPaint()
          } else if (!isImageLoading(src)) {
            loadImage(src)
          }
        }

        onImageLoaded: function(url) {
          if (url === root.imageUrl(root.incomingBackground)) requestPaint()
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          var src = root.imageUrl(root.incomingBackground)
          if (!src || incomingFrame.status !== Image.Ready || root.revealProgress >= 1) return
          if (!isImageLoaded(src)) {
            prepareImage()
            return
          }

          var iw = incomingFrame.sourceSize.width
          var ih = incomingFrame.sourceSize.height
          if (iw <= 0 || ih <= 0 || width <= 0 || height <= 0) return

          var sx = 0
          var sy = 0
          var sw = iw
          var sh = ih
          if (iw / ih > width / height) {
            sw = ih * width / height
            sx = (iw - sw) / 2
          } else {
            sh = iw * height / width
            sy = (ih - sh) / 2
          }

          var center = width / 2
          var reach = width / 2 + Math.abs(slant) * height + 4
          var spread = reach * root.revealProgress
          var leftTop = center - spread
          var leftBottom = center - spread + slant * height
          var rightTop = center + spread
          var rightBottom = center + spread + slant * height

          ctx.save()
          ctx.beginPath()
          ctx.moveTo(center, 0)
          ctx.lineTo(leftTop, 0)
          ctx.lineTo(leftBottom, height)
          ctx.lineTo(center, height)
          ctx.closePath()
          ctx.clip()
          ctx.drawImage(src, sx, sy, sw, sh, 0, 0, width, height)
          ctx.restore()

          ctx.save()
          ctx.beginPath()
          ctx.moveTo(center, 0)
          ctx.lineTo(rightTop, 0)
          ctx.lineTo(rightBottom, height)
          ctx.lineTo(center, height)
          ctx.closePath()
          ctx.clip()
          ctx.drawImage(src, sx, sy, sw, sh, 0, 0, width, height)
          ctx.restore()

          if (!panel.maskReady && root.incomingBackground && root.revealProgress === 0) {
            Qt.callLater(function() {
              panel.maskReady = true
              revealAnimation.restart()
            })
          }
        }

        Connections {
          target: root
          function onRevealProgressChanged() { revealCanvas.requestPaint() }
          function onIncomingBackgroundChanged() {
            panel.maskReady = false
            revealCanvas.prepareImage()
          }
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
