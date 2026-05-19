import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property int batteryThreshold: 10

  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-battery-monitor"
    property bool notifiedLowBattery: false
  }

  function batteryPercentage() {
    var device = UPower.displayDevice
    if (!device || !device.isPresent) return -1
    return Math.round(Number(device.percentage || 0) * 100)
  }

  function isDischarging() {
    var device = UPower.displayDevice
    return !!(device && device.isPresent
      && UPower.onBattery
      && device.state === UPowerDeviceState.Discharging)
  }

  function checkBattery() {
    var level = batteryPercentage()
    if (level < 0) {
      persisted.notifiedLowBattery = false
      return
    }

    if (isDischarging() && level <= batteryThreshold) {
      if (!persisted.notifiedLowBattery) {
        persisted.notifiedLowBattery = true
        sendLowBatteryWarning(level)
      }
    } else {
      persisted.notifiedLowBattery = false
    }
  }

  function sendLowBatteryWarning(level) {
    if (warningProcess.running) return
    warningProcess.command = [
      "omarchy-battery-low",
      String(level)
    ]
    warningProcess.running = true
  }

  Process { id: warningProcess }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkBattery()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() { root.checkBattery() }
  }
}
