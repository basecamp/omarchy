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
  // Must match the headline omarchy-battery-low gives the notification.
  readonly property string lowBatterySummary: "Time to recharge!"
  property string pendingPowerSource: ""
  property bool pendingDismiss: false

  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-battery"
    property bool notifiedLowBattery: false
  }

  function batteryPercentage() {
    return BatteryModel.batteryPercentage(UPower.displayDevice)
  }

  function isDischarging() {
    return BatteryModel.isDischarging(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging)
  }

  function checkBattery() {
    var state = BatteryModel.shouldWarnLowBattery(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging, batteryThreshold, persisted.notifiedLowBattery)
    persisted.notifiedLowBattery = state.notifiedLowBattery
    if (state.notify) sendLowBatteryWarning(state.level)
    else if (state.dismiss) dismissLowBatteryWarning()
  }

  // The warning is critical urgency, so the shell gives it no expiry and it
  // stays on screen until it is clicked. Take it down once the battery is no
  // longer low, which is normally the moment the charger goes in.
  function dismissLowBatteryWarning() {
    // A warning still in flight has not posted its toast yet, so dismissing now
    // would match nothing and strand the popup that lands a moment later. Let
    // the warning finish and dismiss on its way out.
    if (warningProcess.running) {
      pendingDismiss = true
      return
    }
    pendingDismiss = false
    if (dismissProcess.running) return
    dismissProcess.command = ["omarchy-notification-dismiss", lowBatterySummary]
    dismissProcess.running = true
  }

  function sendLowBatteryWarning(level) {
    // Unplugged again before the last warning finished: its toast is the
    // current one, so the dismiss that was waiting on it no longer applies.
    pendingDismiss = false
    if (warningProcess.running) return
    warningProcess.command = [
      "omarchy-battery-low",
      String(level)
    ]
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
    onExited: if (root.pendingDismiss) root.dismissLowBatteryWarning()
  }

  Process { id: dismissProcess }

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
