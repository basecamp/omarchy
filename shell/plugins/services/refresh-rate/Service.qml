import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "RefreshRateModel.js" as RefreshRateModel

Item {
  id: root

  property var shell: null

  // Off unless asked for. Changing what someone's panel does on battery is not
  // a thing to start doing to them on upgrade.
  readonly property var config: shell && shell.shellConfig && shell.shellConfig.refreshRate
    ? shell.shellConfig.refreshRate
    : ({})
  readonly property bool enabled: config.enabled === true
  readonly property int threshold: typeof config.threshold === "number" ? config.threshold : 50

  property var pending: []

  function batteryPercentage() {
    var device = UPower.displayDevice
    if (!device || !device.isPresent) return -1
    return Math.round(Number(device.percentage || 0) * 100)
  }

  function refresh() {
    if (!enabled || monitorsProc.running || applyProc.running) return
    monitorsProc.running = true
  }

  function applyNext() {
    if (root.pending.length === 0) return
    var spec = root.pending[0]
    root.pending = root.pending.slice(1)
    applyProc.command = ["hyprctl", "eval", spec]
    applyProc.running = true
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var monitors = []
        try {
          monitors = JSON.parse(String(text || "[]"))
        } catch (e) {
          return
        }
        root.pending = RefreshRateModel.pendingSpecs(
          monitors, UPower.onBattery, root.batteryPercentage(), root.threshold)
        root.applyNext()
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.applyNext()
  }

  // Charge crossing the threshold is not something UPower raises an event for,
  // so the rate is re-checked on a clock as well as on the mains transition.
  Timer {
    interval: 60000
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() { root.refresh() }
  }
}
