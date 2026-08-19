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
    statusProc.command = ["bash", "-c", "if pgrep -qf '^gpu-screen-recorder'; then [[ -f /tmp/omarchy-screenrecord-paused ]] && echo paused || echo recording; else echo idle; fi"]
    statusProc.running = true
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
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
      root.bar.run("omarchy-capture-screenrecording --stop-recording")
    }
  }
}
