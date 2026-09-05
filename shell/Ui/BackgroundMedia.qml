import QtQuick
import qs.Commons

Item {
  id: root

  property string path: ""
  property int version: 0
  property bool playbackEnabled: true
  property bool loop: true
  property int fadeOutDuration: 0
  readonly property var current: video ? videoLoader.item : imageLoader.item
  readonly property bool ready: current ? current.ready : false
  readonly property bool video: Util.isVideoPath(path)
  readonly property real fadeOutProgress: videoLoader.item ? videoLoader.item.fadeOutProgress : 0
  // Cache-bust images selected in a running lock session. FFmpeg treats the
  // query as part of a local filename, so videos must keep their plain URL.
  readonly property url mediaUrl: path ? Util.fileUrl(path) + (!video && version ? "?v=" + version : "") : ""

  signal finished()

  Loader {
    id: imageLoader
    anchors.fill: parent
    active: root.path !== "" && !root.video
    sourceComponent: imageComponent
  }

  // Loaded by URL rather than from a Component here, so QtMultimedia and its
  // audio dependency closure never map into a session that only shows images.
  Loader {
    id: videoLoader
    anchors.fill: parent
    active: root.path !== "" && root.video
    source: "BackgroundVideo.qml"
  }

  Binding {
    target: videoLoader.item
    property: "mediaSource"
    value: root.mediaUrl
    when: videoLoader.item !== null
  }

  Binding {
    target: videoLoader.item
    property: "playbackEnabled"
    value: root.playbackEnabled
    when: videoLoader.item !== null
  }

  Binding {
    target: videoLoader.item
    property: "loop"
    value: root.loop
    when: videoLoader.item !== null
  }

  Binding {
    target: videoLoader.item
    property: "fadeOutDuration"
    value: root.fadeOutDuration
    when: videoLoader.item !== null
  }

  Connections {
    target: videoLoader.item
    function onFinished() {
      root.finished()
    }
  }

  Component {
    id: imageComponent

    Image {
      readonly property bool ready: status === Image.Ready
      // Path and Loader.active bindings may settle in either order. Guard the
      // source too so a departing image item never hands an MP4 to QQuickImage.
      source: Util.isVideoPath(root.path) ? "" : root.mediaUrl
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: root.version === 0
      sourceSize.width: root.version > 0 ? width : 0
      sourceSize.height: root.version > 0 ? height : 0
    }
  }
}
