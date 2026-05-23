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
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  PwObjectTracker { objects: root.source ? [root.source] : [] }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.muted ? "󰍭" : "󰍬"
    active: root.inUse
    tooltipText: root.muted ? "Microphone muted" : (root.inUse ? "Microphone in use" : "Microphone live")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.bar.run("omarchy-shell omarchy.audio toggle")
      else root.toggleMute()
    }
    onWheelMoved: function(delta) {
      if (!root.source || !root.source.audio) return
      var step = 0.05
      root.source.audio.volume = Math.max(0, Math.min(1, root.volume + (delta > 0 ? step : -step)))
    }
  }
}
