import QtQuick
import QtMultimedia

// Keep Qt Multimedia isolated in this file. Callers load it by URL so a
// session with no startup video never maps the multimedia dependency closure.
// A bare MediaPlayer with no AudioOutput also avoids decoding an unused audio
// stream or opening an audio client for every output.
Item {
  id: root

  property url mediaSource: ""
  property bool playbackEnabled: true
  property bool loop: true
  property bool frameReady: false
  property bool failureReported: false
  readonly property bool ready: frameReady

  signal finished()
  signal failed(string reason)

  function reportFailure(reason) {
    if (failureReported) return
    failureReported = true
    failed(String(reason || "Video playback failed"))
  }

  onMediaSourceChanged: {
    frameReady = false
    failureReported = false
  }

  onPlaybackEnabledChanged: {
    if (playbackEnabled) player.play()
    else player.pause()
  }

  VideoOutput {
    id: output
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectCrop
    endOfStreamPolicy: VideoOutput.KeepLastFrame
  }

  Connections {
    target: output.videoSink
    function onVideoFrameChanged() { root.frameReady = true }
  }

  MediaPlayer {
    id: player
    source: root.mediaSource
    videoOutput: output
    audioOutput: null
    loops: root.loop ? MediaPlayer.Infinite : MediaPlayer.Once
    autoPlay: root.playbackEnabled

    onErrorOccurred: function(error, errorString) { root.reportFailure(errorString) }
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.InvalidMedia) root.reportFailure(errorString)
      else if (mediaStatus === MediaPlayer.EndOfMedia) root.finished()
    }
  }
}
