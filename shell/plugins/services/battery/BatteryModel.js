// How far the charge has to climb back above the threshold before another
// warning is armed. A bare `level > threshold` test re-arms on the rounding
// wobble at the boundary, so a battery hovering at the threshold warns over
// and over.
var LOW_BATTERY_REARM_MARGIN = 5

function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState) {
  return !!(device && device.isPresent && onBattery && device.state === dischargingState)
}

// The warning is a critical toast, so it never expires on its own: something
// has to take it down once the battery is no longer in trouble. That makes
// this a three-way decision rather than a "should I warn" test — warn, clear
// the standing warning, or leave things as they are.
function lowBatteryWarningState(device, onBattery, dischargingState, threshold, alreadyNotified) {
  var level = batteryPercentage(device)
  var recovered = level < 0 || !isDischarging(device, onBattery, dischargingState) || level > threshold + LOW_BATTERY_REARM_MARGIN

  if (recovered) return { level: level, notify: false, dismiss: !!alreadyNotified, notifiedLowBattery: false }
  if (level > threshold) return { level: level, notify: false, dismiss: false, notifiedLowBattery: !!alreadyNotified }
  return { level: level, notify: !alreadyNotified, dismiss: false, notifiedLowBattery: true }
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    lowBatteryWarningState: lowBatteryWarningState
  }
}
