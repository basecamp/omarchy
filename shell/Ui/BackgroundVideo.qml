import QtQuick
import QtMultimedia

// Deliberately a bare MediaPlayer and VideoOutput rather than the Video
// convenience type: Video always builds an AudioOutput, and a muted sink still
// decodes the audio stream and opens an audio client on every output.
Item {
  id: root

  property url mediaSource: ""
  property bool playbackEnabled: true
  property bool loop: true
  readonly property bool ready: player.hasVideo

  signal finished()

  onPlaybackEnabledChanged: {
    if (playbackEnabled) player.play()
    else player.pause()
  }

  VideoOutput {
    id: output
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectCrop
  }

  MediaPlayer {
    id: player
    source: root.mediaSource
    videoOutput: output
    audioOutput: null
    loops: root.loop ? MediaPlayer.Infinite : 1
    autoPlay: root.playbackEnabled
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.EndOfMedia) root.finished()
    }
    onErrorOccurred: root.finished()
  }
}
