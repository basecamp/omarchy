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
  property string pendingPowerSourceHook: ""
  property string lastPowerSource: ""

  // UPower hydrates OnBattery before the display device becomes ready. Seed
  // the baseline then, including when this service loads into an existing shell.
  Component.onCompleted: initializePowerSource()

  function initializePowerSource() {
    if (UPower.displayDevice.ready && lastPowerSource === "")
      lastPowerSource = UPower.onBattery ? "battery" : "ac"
  }

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

  function dispatchPowerSourceHook() {
    if (lastPowerSource === "") return
    var source = UPower.onBattery ? "battery" : "ac"
    if (source === lastPowerSource) return
    lastPowerSource = source
    pendingPowerSourceHook = source
    if (!powerSourceHookProcess.running) runPendingPowerSourceHook()
  }

  function runPendingPowerSourceHook() {
    powerSourceHookProcess.command = ["omarchy-hook", "power-source-change", pendingPowerSourceHook]
    pendingPowerSourceHook = ""
    powerSourceHookProcess.running = true
  }

  Process { id: warningProcess }

  Process {
    id: powerProfileProcess
    onExited: if (root.pendingPowerSource !== "") root.runPendingPowerProfile()
  }

  Process {
    id: powerSourceHookProcess
    onExited: if (root.pendingPowerSourceHook !== "") root.runPendingPowerSourceHook()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkBattery()
  }

  Connections {
    target: UPower.displayDevice
    function onReadyChanged() { root.initializePowerSource() }
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.checkBattery()
      root.applyPowerProfile()
      root.dispatchPowerSourceHook()
    }
  }
}
