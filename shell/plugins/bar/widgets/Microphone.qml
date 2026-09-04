import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.microphone"


  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool muted: source && source.audio ? source.audio.muted : true
  readonly property real volume: source && source.audio ? source.audio.volume : 0
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  readonly property var activeStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && node.isStream && node.isSink === false && !node.audio?.muted) list.push(node)
    }
    return list
  }

  readonly property bool inUse: activeStreams.length > 0 && !muted

  visible: source !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleMute() {
    var nextMute = !muted
    if (source && source.audio) source.audio.muted = nextMute
    var target = (source && source.id !== undefined) ? String(source.id) : "@DEFAULT_AUDIO_SOURCE@"
    Quickshell.execDetached(["wpctl", "set-mute", target, nextMute ? "1" : "0"])
  }

  PwObjectTracker { objects: root.source ? [root.source] : [] }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.muted ? "󰍭" : "󰍬"
    active: root.inUse
    tooltipText: root.muted ? "Microphone muted" : (root.inUse ? "Microphone in use" : "Microphone live")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.bar.run("omarchy-shell shell toggle omarchy.audio")
      else root.toggleMute()
    }
    onWheelMoved: function(delta) {
      if (!root.source || !root.source.audio) return
      var step = 0.05
      var nextVol = Math.max(0, Math.min(1, root.volume + (delta > 0 ? step : -step)))
      root.source.audio.volume = nextVol
      var target = (root.source && root.source.id !== undefined) ? String(root.source.id) : "@DEFAULT_AUDIO_SOURCE@"
      Quickshell.execDetached(["wpctl", "set-volume", target, nextVol.toFixed(3)])
    }
  }
}
