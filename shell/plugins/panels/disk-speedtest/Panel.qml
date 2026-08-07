import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The shared gauge-cluster overlay dressed for the disk speed test: write and
// read dials in MB/s, titled with the model of the disk under test. One
// omarchy-disk-speedtest run streams both phases and cleans up after itself,
// so dismissal only has to stop the process.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool running: false
  property bool expectedStop: false
  property bool pendingRun: false
  property string phase: ""             // "write" | "read" | ""
  property string diskName: ""
  property string writeMBps: ""
  property string readMBps: ""
  property string error: ""
  property string stderrText: ""

  function open(payloadJson) {
    opened = true
    runTest()
  }

  // Host-initiated close (`shell hide`). The user-initiated paths (Esc, the
  // scrim) route through shell.hide so the host's open-panel state stays
  // consistent, and land back here.
  function close() {
    opened = false
    pendingRun = false
    // Clear the phase before killing the process, so onExited reads the stop
    // as a dismissal rather than a failed run.
    phase = ""
    running = false
    if (proc.running) {
      expectedStop = true
      proc.running = false
    }
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "omarchy.disk-speedtest")
    else close()
  }

  function runTest() {
    if (proc.running) {
      // A dismissal's SIGTERM is still in flight; Process.running stays true
      // until the child exits, so queue the fresh run for onExited.
      if (expectedStop) pendingRun = true
      return
    }
    error = ""
    diskName = ""
    writeMBps = ""
    readMBps = ""
    stderrText = ""
    phase = "write"
    running = true
    proc.running = true
  }

  function toRate(raw) {
    var value = parseFloat(raw)
    return isFinite(value) && value > 0 ? value : 0
  }

  // Lines are "disk <model>", then "write <MB/s>" once a second, then
  // "read <MB/s>". The phase follows whichever figure is streaming.
  function updateLine(line) {
    var parts = String(line).trim().split(/\s+/)
    if (parts.length < 2) return
    if (parts[0] === "disk") {
      diskName = parts.slice(1).join(" ")
      return
    }
    var value = parseFloat(parts[1])
    if (!isFinite(value) || value < 0) return
    if (parts[0] === "write") {
      phase = "write"
      writeMBps = String(value)
    } else if (parts[0] === "read") {
      phase = "read"
      readMBps = String(value)
    } else {
      return
    }
    error = ""
  }

  Process {
    id: proc
    command: ["omarchy-disk-speedtest"]
    stdout: SplitParser { onRead: function(line) { root.updateLine(line) } }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.stderrText = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (root.pendingRun) {
        root.pendingRun = false
        root.expectedStop = false
        if (root.opened) Qt.callLater(root.runTest)
        return
      }

      if (!root.expectedStop && exitCode !== 0) {
        root.error = root.stderrText || "Disk speed test failed"
        root.phase = ""
        root.running = false
        return
      }

      root.expectedStop = false
      root.phase = ""
      root.running = false
    }
  }

  SpeedTestOverlay {
    fontFamily: Style.font.family
    layerNamespace: "omarchy-disk-speedtest"
    title: root.diskName
    leftLabel: "WRITE"
    rightLabel: "READ"
    unit: "MB/s"
    runAgainTooltip: "Measure again"
    running: root.running
    leftValue: root.toRate(root.writeMBps)
    rightValue: root.toRate(root.readMBps)
    leftLive: root.running && root.phase === "write"
    rightLive: root.running && root.phase === "read"
    error: root.error
    open: root.opened
    scaleStops: [500, 1000, 2500, 5000, 10000, 15000]
    onCloseRequested: root.dismiss()
    onRunAgainRequested: root.runTest()
  }
}
