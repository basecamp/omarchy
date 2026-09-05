import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property int batteryThreshold: 10
  property string pendingPowerSource: ""
  property string pendingWarningArg: ""

  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-battery"
    property bool notifiedLowBattery: false
  }

  // Deliberately not persisted, and not in the block above: this has to reset
  // exactly when the shell process restarts, because that is the event that
  // restores a critical toast from disk while dropping the latch remembering
  // it was sent.
  property bool staleWarningSwept: false

  function batteryPercentage() {
    return BatteryModel.batteryPercentage(UPower.displayDevice)
  }

  function isDischarging() {
    return BatteryModel.isDischarging(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging)
  }

  function checkBattery() {
    var state = BatteryModel.lowBatteryWarningState(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging, batteryThreshold, persisted.notifiedLowBattery, staleWarningSwept)
    persisted.notifiedLowBattery = state.notifiedLowBattery
    staleWarningSwept = state.staleWarningSwept
    if (state.notify) sendLowBatteryWarning(state.level)
    else if (state.dismiss) clearLowBatteryWarning()
  }

  function sendLowBatteryWarning(level) {
    queueWarningCommand(String(level))
  }

  // Plugging in answers the warning, so the toast goes with it rather than
  // waiting to be swatted away by hand.
  function clearLowBatteryWarning() {
    queueWarningCommand("--clear")
  }

  // Sending and clearing race each other when they overlap: a clear that
  // starts while a warning is still launching finishes first, and the warning
  // then puts a toast up after the latch that would clear it has been reset,
  // leaving it there for good. One process, one pending command, so they run
  // in the order they were decided. A newer intent replaces the pending one —
  // it was decided from a newer reading.
  function queueWarningCommand(arg) {
    pendingWarningArg = arg
    if (!warningProcess.running) runPendingWarningCommand()
  }

  function runPendingWarningCommand() {
    warningProcess.command = ["omarchy-battery-low", pendingWarningArg]
    pendingWarningArg = ""
    warningProcess.running = true
  }

  function applyPowerProfile() {
    pendingPowerSource = UPower.onBattery ? "battery" : "ac"
    if (!powerProfileProcess.running) runPendingPowerProfile()
  }

  function runPendingPowerProfile() {
    powerProfileProcess.command = ["omarchy-powerprofiles-set", pendingPowerSource]
    pendingPowerSource = ""
    powerProfileProcess.running = true
  }

  Process {
    id: warningProcess
    onExited: if (root.pendingWarningArg !== "") root.runPendingWarningCommand()
  }

  Process {
    id: powerProfileProcess
    onExited: if (root.pendingPowerSource !== "") root.runPendingPowerProfile()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkBattery()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.checkBattery()
      root.applyPowerProfile()
    }
  }
}
