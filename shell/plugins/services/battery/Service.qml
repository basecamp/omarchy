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
  // UPower's first onBattery / display-device values can still reflect the
  // pre-suspend discharging state for a few seconds after shell start (#7679).
  // Hold low-battery warnings until settleTimer completes; power profiles still
  // apply immediately on charger changes.
  property bool lowBatteryChecksReady: false

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
    if (!lowBatteryChecksReady) return
    var state = BatteryModel.shouldWarnLowBattery(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging, batteryThreshold, persisted.notifiedLowBattery)
    persisted.notifiedLowBattery = state.notifiedLowBattery
    if (state.notify) sendLowBatteryWarning(state.level)
  }

  function sendLowBatteryWarning(level) {
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

  Process { id: warningProcess }

  Process {
    id: powerProfileProcess
    onExited: if (root.pendingPowerSource !== "") root.runPendingPowerProfile()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    // Wait for UPower's AC state to settle before the first check. An immediate
    // run on shell start can still see the pre-death discharging state after a
    // battery-empty suspend, and fire "Time to recharge!" while already on AC (#7679).
    triggeredOnStart: false
    onTriggered: root.checkBattery()
  }

  // First evaluation after UPower has had a moment to report the real charger state.
  Timer {
    id: settleTimer
    interval: 5000
    running: true
    repeat: false
    onTriggered: {
      root.lowBatteryChecksReady = true
      root.checkBattery()
    }
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      // Always switch profiles immediately; low-battery warnings wait for settle.
      root.applyPowerProfile()
      root.checkBattery()
    }
  }
}
