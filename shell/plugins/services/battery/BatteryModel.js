function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState) {
  return !!(device && device.isPresent && onBattery && device.state === dischargingState)
}

// A weak charger can leave the battery hovering on the threshold, flipping
// between charging and discharging every few seconds. The latch alone clears
// on every flip, so the warning also needs a cooldown before it may fire again.
function shouldWarnLowBattery(device, onBattery, dischargingState, threshold, alreadyNotified, lastNotifiedAt, now, cooldown) {
  var level = batteryPercentage(device)
  if (level < 0) return { level: level, notify: false, notifiedLowBattery: false, lastNotifiedAt: lastNotifiedAt }

  var low = isDischarging(device, onBattery, dischargingState) && level <= threshold
  var cooledDown = !lastNotifiedAt || now - lastNotifiedAt >= cooldown
  var notify = low && !alreadyNotified && cooledDown

  return {
    level: level,
    notify: notify,
    notifiedLowBattery: low,
    lastNotifiedAt: notify ? now : lastNotifiedAt
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    shouldWarnLowBattery: shouldWarnLowBattery
  }
}
