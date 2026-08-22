import QtQuick
import Quickshell.Io

Item {
  id: root

  property string state: "idle"
  readonly property bool capturing: state === "recording" || state === "streaming"
  readonly property bool transcribing: state === "transcribing"
  readonly property bool busy: capturing || transcribing

  property int levelSlots: 22
  property var levels: []
  property real pendingPeak: 0
  property double startedAt: 0
  property int elapsed: 0

  function resetLevels() {
    var empty = []
    for (var i = 0; i < levelSlots; i++) empty.push(0)
    levels = empty
    pendingPeak = 0
  }

  function updateStatus(raw) {
    try {
      var data = JSON.parse(String(raw || "").trim())
      state = String(data.alt || data.class || "idle")
    } catch (e) {
    }
  }

  function updateAudio(raw) {
    try {
      var frame = JSON.parse(String(raw || "").trim())
      if (typeof frame.peak === "number") pendingPeak = Math.max(pendingPeak, frame.peak)
    } catch (e) {
    }
  }

  Component.onCompleted: {
    resetLevels()
    statusProc.running = true
  }

  onCapturingChanged: {
    if (capturing) {
      startedAt = Date.now()
      elapsed = 0
      bridgeProc.running = true
    } else {
      bridgeRestart.stop()
      bridgeProc.running = false
      resetLevels()
    }
  }

  Process {
    id: statusProc
    command: ["bash", "-c", "if omarchy-cmd-present voxtype; then exec omarchy-voxtype-status; else exit 127; fi"]
    stdout: SplitParser {
      onRead: function(data) { root.updateStatus(data) }
    }
    onExited: function(exitCode) {
      root.state = "idle"
      root.resetLevels()
      if (exitCode !== 127) statusRestart.restart()
    }
  }

  Timer {
    id: statusRestart
    interval: 1000
    onTriggered: statusProc.running = true
  }

  Process {
    id: bridgeProc
    command: ["bash", "-c", "if omarchy-cmd-present voxtype-audio-bridge; then exec voxtype-audio-bridge; else exit 127; fi"]
    stdout: SplitParser {
      onRead: function(data) { root.updateAudio(data) }
    }
    onExited: function(exitCode) {
      if (root.capturing && exitCode !== 127) bridgeRestart.restart()
    }
  }

  Timer {
    id: bridgeRestart
    interval: 500
    onTriggered: if (root.capturing) bridgeProc.running = true
  }

  Timer {
    running: root.capturing
    interval: 55
    repeat: true
    onTriggered: {
      var next = root.levels.slice(1)
      next.push(Math.max(0, Math.min(1, root.pendingPeak)))
      root.levels = next
      root.pendingPeak = 0
    }
  }

  Timer {
    running: root.capturing
    interval: 250
    repeat: true
    onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
  }
}
