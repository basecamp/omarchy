function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState) {
  return !!(device && device.isPresent && onBattery && device.state === dischargingState)
}

function shouldWarnLowBattery(device, onBattery, dischargingState, threshold, alreadyNotified, alreadyDismissed) {
  var level = batteryPercentage(device)
  var low = level >= 0 && isDischarging(device, onBattery, dischargingState) && level <= threshold

  return {
    level: level,
    notify: low && !alreadyNotified,
    dismiss: !low && !alreadyDismissed,
    notifiedLowBattery: low,
    dismissedLowBattery: !low
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    shouldWarnLowBattery: shouldWarnLowBattery
  }
}
