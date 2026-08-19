import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property bool recording: false
  property bool paused: false

  active: recording
  activeText: paused ? "" : "󰻂"
  inactiveText: "󰻂"
  activeTooltipText: paused ? "Resume recording" : "Stop recording"
  inactiveTooltipText: "Screen Recording"

  function refresh() {
    if (!root.bar || statusProc.running) return
    statusProc.command = ["bash", "-c", "if pgrep -f '^gpu-screen-recorder' >/dev/null 2>&1; then [[ -f /tmp/omarchy-screenrecord-paused ]] && echo paused || echo recording; else echo idle; fi"]
    statusProc.running = true
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  // The script pokes the indicator on start/pause/stop, but that IPC can lose
  // a race right after a shell restart and leave the indicator stuck on idle
  // (so a mid-capture click opens the start menu instead of the chooser). A 2s
  // tick lets the indicator catch up on its own from the marker file + pgrep.
  Timer {
    interval: 2000
    running: root.bar !== null
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    stdout: SplitParser {
      onRead: function(data) {
        var state = String(data).trim()
        if (state === "paused") {
          root.recording = true
          root.paused = true
        } else if (state === "recording") {
          root.recording = true
          root.paused = false
        } else {
          root.recording = false
          root.paused = false
        }
      }
    }
  }

  onPressed: function() {
    if (!root.bar) return
    if (!root.recording) {
      root.bar.run("omarchy-menu toggle trigger.capture.screenrecord")
    } else if (root.paused) {
      root.bar.run("omarchy-capture-screenrecording --pause-recording")
    } else {
      root.bar.run("omarchy-capture-screenrecording --prompt")
    }
  }
}
