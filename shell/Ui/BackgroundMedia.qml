import QtQuick
import QtMultimedia
import qs.Commons

Item {
  id: root

  property string path: ""
  property int version: 0
  property bool playbackEnabled: true
  readonly property bool ready: loader.item ? loader.item.ready : false
  readonly property bool video: Util.isVideoPath(path)
  // Cache-bust images selected in a running lock session. FFmpeg treats the
  // query as part of a local filename, so videos must keep their plain URL.
  readonly property url mediaUrl: path ? Util.fileUrl(path) + (!video && version ? "?v=" + version : "") : ""

  onPlaybackEnabledChanged: {
    if (!video || !loader.item) return
    if (playbackEnabled) loader.item.play()
    else loader.item.pause()
  }

  Loader {
    id: loader
    anchors.fill: parent
    active: root.path !== ""
    sourceComponent: root.video ? videoComponent : imageComponent
  }

  Component {
    id: imageComponent

    Image {
      readonly property bool ready: status === Image.Ready
      source: root.mediaUrl
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: root.version === 0
      smooth: true
      mipmap: true
      sourceSize.width: root.version > 0 ? width : 0
      sourceSize.height: root.version > 0 ? height : 0
    }
  }

  Component {
    id: videoComponent

    Video {
      readonly property bool ready: hasVideo
      source: root.mediaUrl
      fillMode: VideoOutput.PreserveAspectCrop
      loops: MediaPlayer.Infinite
      autoPlay: root.playbackEnabled
      muted: true
    }
  }
}
