import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../../panels/power/Model.js" as PowerModel
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property var powerDevices: UPower.devices ? UPower.devices.values : []
  property string pendingPowerSource: ""

  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-battery"
    property bool notifiedLowBattery: false
    property bool actedCriticalBattery: false
    property string previousEnergy: ""
    property string previousSize: ""
    property string previousRate: ""
    property string previousState: ""
    property string previousSampleMs: "0"
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function previousSample() {
    if (!persisted.previousEnergy) return {}
    return {
      energy: persisted.previousEnergy,
      size: persisted.previousSize,
      rate: persisted.previousRate,
      state: persisted.previousState,
      _sampleMs: persisted.previousSampleMs
    }
  }

  function rememberSample(sample) {
    var next = sample || {}
    persisted.previousEnergy = String(next.energy || "")
    persisted.previousSize = String(next.size || "")
    persisted.previousRate = String(next.rate || "")
    persisted.previousState = String(next.state || "")
    persisted.previousSampleMs = String(next._sampleMs || "0")
  }

  function checkBattery() {
    var snap = PowerModel.liveEnergySnapshot(root.powerDevices, null, previousSample(), Date.now(), upowerStates())
    rememberSample(snap.sample)

    var discharging = !!(UPower.onBattery && snap.discharging)
    var warn = BatteryModel.shouldWarnLowBattery(snap.fraction, UPower.onBattery, discharging, persisted.notifiedLowBattery)
    persisted.notifiedLowBattery = warn.notifiedLowBattery
    if (warn.notify) sendLowBatteryWarning(warn.level)

    var act = BatteryModel.shouldActCriticalBattery(snap.fraction, UPower.onBattery, discharging, persisted.actedCriticalBattery)
    persisted.actedCriticalBattery = act.actedCriticalBattery
    if (act.act) sendCriticalAction(act.level)
  }

  function sendLowBatteryWarning(level) {
    if (warningProcess.running) return
    warningProcess.command = [
      "omarchy-battery-low",
      String(level)
    ]
    warningProcess.running = true
  }

  function sendCriticalAction(level) {
    if (criticalProcess.running) return
    criticalProcess.command = [
      "omarchy-battery-critical",
      String(level)
    ]
    criticalProcess.running = true
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
  Process { id: criticalProcess }

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
      if (!UPower.onBattery) {
        persisted.notifiedLowBattery = false
        persisted.actedCriticalBattery = false
      }
      root.checkBattery()
      root.applyPowerProfile()
    }
  }
}
