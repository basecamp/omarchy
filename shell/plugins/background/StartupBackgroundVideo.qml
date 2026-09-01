import QtQuick
import qs.Commons

Item {
  id: root

  property bool active: false
  property bool obscured: false
  property string videoPath: ""
  property string firstFramePath: ""
  property bool completed: false
  property bool finishing: false
  property real videoBlend: 0
  readonly property bool videoReady: videoLoader.item ? videoLoader.item.ready : false

  signal playbackComplete()

  visible: active && !completed && opacity > 0

  function finish(animated) {
    if (completed || finishing) return

    decodeTimeout.stop()
    playbackTimeout.stop()
    if (animated) {
      finishing = true
      finishFade.restart()
    } else {
      finalize()
    }
  }

  function finalize() {
    completed = true
    finishing = false
    playbackComplete()
  }

  onActiveChanged: {
    if (!active) {
      decodeTimeout.stop()
      playbackTimeout.stop()
      return
    }

    opacity = 1
    videoBlend = 0
    completed = false
    finishing = false
    if (!videoPath || obscured) finish(false)
    else decodeTimeout.restart()
  }

  onObscuredChanged: if (obscured && active) finish(false)

  onVideoReadyChanged: {
    if (!videoReady || completed) return
    decodeTimeout.stop()
    videoBlend = 1
    playbackTimeout.restart()
  }

  Image {
    anchors.fill: parent
    source: root.firstFramePath ? Util.fileUrl(root.firstFramePath) : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    opacity: 1 - root.videoBlend
    visible: source !== "" && opacity > 0
  }

  // Loading by URL is essential: an inline Component would resolve the
  // QtMultimedia import while compiling this file even when no video exists.
  Loader {
    id: videoLoader
    anchors.fill: parent
    active: root.active && !root.completed && !root.obscured
    source: Qt.resolvedUrl("../../Ui/BackgroundVideo.qml")
    opacity: root.videoBlend
  }

  Binding {
    target: videoLoader.item
    property: "mediaSource"
    value: Util.fileUrl(root.videoPath)
    when: videoLoader.item !== null
  }

  Binding {
    target: videoLoader.item
    property: "loop"
    value: false
    when: videoLoader.item !== null
  }

  Binding {
    target: videoLoader.item
    property: "playbackEnabled"
    value: root.active && !root.completed && !root.finishing && !root.obscured
    when: videoLoader.item !== null
  }

  Connections {
    target: videoLoader.item
    function onFinished() { root.finish(true) }
    function onFailed(reason) { root.finish(true) }
  }

  Behavior on videoBlend {
    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
  }

  Timer {
    id: decodeTimeout
    interval: 5000
    repeat: false
    onTriggered: root.finish(true)
  }

  // A malformed theme must not turn an optional flourish into an unbounded
  // decoder workload. Normal Omarchy startup clips are only a few seconds.
  Timer {
    id: playbackTimeout
    interval: 30000
    repeat: false
    onTriggered: root.finish(true)
  }

  NumberAnimation {
    id: finishFade
    target: root
    property: "opacity"
    to: 0
    duration: 240
    easing.type: Easing.InOutCubic
    onFinished: root.finalize()
  }
}
