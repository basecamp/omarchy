import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property bool recording: false

  active: recording
  activeText: "󰻂"
  inactiveText: "󰻂"
  activeTooltipText: "Stop recording"
  inactiveTooltipText: "Screen Recording"

  // pgrep is fast; if the Process never leaves running (onExited lost after an
  // abrupt recorder death, handler throw, etc.), refresh() would bail forever
  // and the icon stay stuck on the last known state. Cap each probe and keep
  // polling so a killed gpu-screen-recorder is noticed without a shell restart.
  function refresh() {
    if (!root.bar)
      return

    if (statusProc.running) {
      if (!probeWatchdog.running)
        probeWatchdog.restart()
      return
    }

    statusProc.command = ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    statusProc.running = true
    probeWatchdog.restart()
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() {
      root.refresh()
    }
  }

  Process {
    id: statusProc
    onExited: function (exitCode) {
      probeWatchdog.stop()
      root.recording = exitCode === 0
    }
  }

  Timer {
    id: probeWatchdog
    interval: 2000
    repeat: false
    onTriggered: {
      if (!statusProc.running)
        return
      // Drop the stuck Process handle so the next poll can start a fresh pgrep.
      statusProc.running = false
      root.refresh()
    }
  }

  Timer {
    id: pollTimer
    // Abnormal kills skip omarchy-capture-screenrecording's indicator toggle;
    // poll so the bar catches up without waiting for another IPC refresh.
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  onPressed: function () {
    if (root.bar) {
      root.bar.run(root.recording ? "omarchy-capture-screenrecording --stop-recording" : "omarchy-menu toggle trigger.capture.screenrecord")
    }
  }
}
