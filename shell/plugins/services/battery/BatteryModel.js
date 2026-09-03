function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState) {
  return !!(device && device.isPresent && onBattery && device.state === dischargingState)
}

function shouldWarnLowBattery(device, onBattery, dischargingState, threshold, alreadyNotified) {
  var level = batteryPercentage(device)
  if (level < 0) return { level: level, notify: false, notifiedLowBattery: false }

  var low = isDischarging(device, onBattery, dischargingState) && level <= threshold

  // Hysteresis: once warned, stay latched until the battery recovers well above
  // the threshold. Clearing the latch the moment the device is not both
  // discharging and at/under the threshold lets a brief charging/pending/unknown
  // UPower blip at a still-low percentage re-arm the warning, so the next poll
  // re-fires the critical notification and copies stack up on screen.
  var recovered = level >= threshold + 10
  return {
    level: level,
    notify: low && !alreadyNotified,
    notifiedLowBattery: (alreadyNotified || low) && !recovered
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    shouldWarnLowBattery: shouldWarnLowBattery
  }
}
