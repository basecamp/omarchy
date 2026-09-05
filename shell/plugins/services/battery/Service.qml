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
  // -1 for none. A level is always 0..threshold when one is owed, because
  // checkBattery only asks for a warning on a present, discharging battery.
  property int pendingWarningLevel: -1

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
  //
  // Both commands are spawned, and the dismiss takes down every toast whose
  // summary contains the headline, so the two must never overlap. A dismiss
  // racing a warning either matches nothing and strands the toast that lands
  // just behind it, or sweeps that toast away along with the one it was sent
  // for. Neither is recoverable: checkBattery latches notifiedLowBattery
  // before either command runs and computes both `notify` and `dismiss` from
  // that latch, so a request dropped here is never recomputed by a later
  // poll. The user is left either with a warning that never expires and no
  // longer applies, or under the threshold with nothing on screen. So each
  // request is issued only when the other process has exited, and held until
  // then.
  function dismissLowBatteryWarning() {
    // Charging again, so a warning we were holding no longer applies.
    pendingWarningLevel = -1
    if (warningProcess.running || dismissProcess.running) {
      pendingDismiss = true
      return
    }
    pendingDismiss = false
    dismissProcess.command = ["omarchy-notification-dismiss", lowBatterySummary]
    dismissProcess.running = true
  }

  function sendLowBatteryWarning(level) {
    // Unplugged again before the dismiss went out, so it no longer applies.
    pendingDismiss = false
    if (dismissProcess.running) {
      pendingWarningLevel = level
      return
    }
    pendingWarningLevel = -1
    // A warning already on its way is this same warning.
    if (warningProcess.running) return
    warningProcess.command = [
      "omarchy-battery-low",
      String(level)
    ]
    warningProcess.running = true
  }

  // Only ever one of the two is held: each function clears the other's.
  function runPendingBatteryNotification() {
    if (pendingDismiss) dismissLowBatteryWarning()
    else if (pendingWarningLevel >= 0) sendLowBatteryWarning(pendingWarningLevel)
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
    onExited: root.runPendingBatteryNotification()
  }

  Process {
    id: dismissProcess
    onExited: root.runPendingBatteryNotification()
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
