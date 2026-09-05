function parseStatusPercent(info) {
  if (!info || info.percentage == null || info.percentage === "") return -1
  var n = parseInt(String(info.percentage), 10)
  return isNaN(n) ? -1 : Math.max(0, Math.min(100, n))
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function batteryPercentage(device, info) {
  var fromStatus = parseStatusPercent(info)
  if (fromStatus >= 0) return fromStatus
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState, info) {
  if (!onBattery) return false
  if (info && info.state === "discharging") return true
  return !!(device && device.isPresent && device.state === dischargingState)
}

function shouldWarnLowBattery(device, onBattery, dischargingState, threshold, alreadyNotified, info) {
  var level = batteryPercentage(device, info)
  if (level < 0) return { level: level, notify: false, notifiedLowBattery: false }

  var low = isDischarging(device, onBattery, dischargingState, info) && level <= threshold
  return {
    level: level,
    notify: low && !alreadyNotified,
    notifiedLowBattery: low
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatusPercent: parseStatusPercent,
    parseKeyValue: parseKeyValue,
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    shouldWarnLowBattery: shouldWarnLowBattery
  }
}
