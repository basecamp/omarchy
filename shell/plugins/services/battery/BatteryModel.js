var LOW_BATTERY_WARN_PERCENT = 10
var LOW_BATTERY_ACTION_PERCENT = 2

function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState) {
  return !!(device && device.isPresent && onBattery && device.state === dischargingState)
}

function livePercent(fraction) {
  if (!(fraction >= 0)) return -1
  return Math.round(Number(fraction) * 100)
}

function shouldWarnLowBattery(fraction, onBattery, discharging, alreadyNotified, warnPercent) {
  var threshold = warnPercent === undefined || warnPercent === null ? LOW_BATTERY_WARN_PERCENT : Number(warnPercent)
  var level = livePercent(fraction)
  if (level < 0) return { level: level, notify: false, notifiedLowBattery: false }

  var low = !!(onBattery && discharging && level <= threshold)
  return {
    level: level,
    notify: low && !alreadyNotified,
    notifiedLowBattery: low
  }
}

function shouldActCriticalBattery(fraction, onBattery, discharging, alreadyActed, actionPercent) {
  var threshold = actionPercent === undefined || actionPercent === null ? LOW_BATTERY_ACTION_PERCENT : Number(actionPercent)
  var level = livePercent(fraction)
  if (level < 0) return { level: level, act: false, actedCriticalBattery: false }

  var critical = !!(onBattery && discharging && level <= threshold)
  return {
    level: level,
    act: critical && !alreadyActed,
    actedCriticalBattery: critical
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    LOW_BATTERY_WARN_PERCENT: LOW_BATTERY_WARN_PERCENT,
    LOW_BATTERY_ACTION_PERCENT: LOW_BATTERY_ACTION_PERCENT,
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    shouldWarnLowBattery: shouldWarnLowBattery,
    shouldActCriticalBattery: shouldActCriticalBattery
  }
}
