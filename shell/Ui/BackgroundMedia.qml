import QtQuick
import qs.Commons

Item {
  id: root

  property string path: ""
  property int version: 0
  property bool playbackEnabled: true
  readonly property var current: video ? videoLoader.item : imageLoader.item
  readonly property bool ready: current ? current.ready : false
  readonly property bool video: Util.isVideoPath(path)
  // Cache-bust images selected in a running lock session. FFmpeg treats the
  // query as part of a local filename, so videos must keep their plain URL.
  readonly property url mediaUrl: path ? Util.fileUrl(path) + (!video && version ? "?v=" + version : "") : ""

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

  Component {
    id: imageComponent

    Image {
      readonly property bool ready: status === Image.Ready
      source: root.mediaUrl
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: root.version === 0
      sourceSize.width: root.version > 0 ? width : 0
      sourceSize.height: root.version > 0 ? height : 0
    }
  }
}
