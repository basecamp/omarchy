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
  property int fadeOutDuration: 0
  readonly property bool ready: player.hasVideo
  readonly property real fadeOutProgress: fadeOutDuration > 0 && player.duration > 0
    ? Math.max(0, Math.min(1, (player.position - (player.duration - fadeOutDuration)) / fadeOutDuration))
    : 0

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
