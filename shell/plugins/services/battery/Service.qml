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
  readonly property string lowBatteryNotificationApp: "omarchy-battery"
  readonly property string legacyLowBatteryNotificationApp: "omarchy-action"
  readonly property string lowBatteryNotificationSummary: "Time to recharge!"
  readonly property var batteryDevice: UPower.displayDevice
  readonly property var notificationService: shell ? shell.firstPartyServiceFor("omarchy.notifications") : null
  property string pendingPowerSource: ""

  onNotificationServiceChanged: dismissLowBatteryWarning()

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

  function dismissLowBatteryWarning() {
    if (!BatteryModel.shouldDismissLowBatteryWarning(batteryDevice, UPower.onBattery)) return
    if (!notificationService) return

    notificationService.dismissByApp(lowBatteryNotificationApp)
    // Warnings persisted before the dedicated app identity was introduced
    // used omarchy-action, so match their exact headline during the upgrade.
    notificationService.dismissByApp(legacyLowBatteryNotificationApp, lowBatteryNotificationSummary)
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
    triggeredOnStart: true
    onTriggered: root.checkBattery()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.checkBattery()
      root.dismissLowBatteryWarning()
      root.applyPowerProfile()
    }
  }

  Connections {
    target: root.batteryDevice
    function onReadyChanged() {
      // On AC, clear a warning latch preserved while UPower was unready.
      // On battery, the regular timer avoids racing popup restoration with
      // a duplicate warning during shell startup.
      if (!UPower.onBattery) root.checkBattery()
      root.dismissLowBatteryWarning()
    }
  }

  Connections {
    target: root.notificationService
    function onPopupAdded(appName, summary) {
      if (appName === root.lowBatteryNotificationApp
          || (appName === root.legacyLowBatteryNotificationApp
              && summary === root.lowBatteryNotificationSummary)) {
        root.dismissLowBatteryWarning()
      }
    }
  }
}
