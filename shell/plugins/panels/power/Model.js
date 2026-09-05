function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
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

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function statusPercent(info) {
  if (!info || info.percentage == null || info.percentage === "") return -1
  var n = parseInt(String(info.percentage), 10)
  return isNaN(n) ? -1 : Math.max(0, Math.min(100, n))
}

function statusState(info) {
  return info && info.state ? String(info.state) : ""
}

function batteryFraction(device, info) {
  var p = statusPercent(info)
  if (p >= 0) return p / 100
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function chargeThresholdActive(device, onBattery, states, info) {
  var st = statusState(info)
  if (st === "holding") return true
  if (st === "fully-charged" || st === "charging" || st === "discharging") return false

  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d, info)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  // Stalled charging at a hold point is a trickle under 0.2W.
  // Do not treat a multi-hour UPower "time to full" as a threshold: that is
  // the stuck energy-full bug, not a charge limit.
  return Number(d.changeRate || 0) <= 0.2
}

function batteryIcon(device, onBattery, states, info) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var fraction = batteryFraction(d, info)
  var index = Math.max(0, Math.min(9, Math.floor(fraction * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states, info)
  var st = statusState(info)

  if (threshold) return defaultIcons[index]
  if (st === "fully-charged" || d.state === states.FullyCharged) return "󰂅"
  if (!onBattery && st !== "fully-charged") return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states, info) {
  var d = device || {}
  if (!d.isPresent) return ""

  var st = statusState(info)
  var percentage = batteryFraction(d, info)
  if (chargeThresholdActive(d, onBattery, states, info)) return "Threshold"
  if (onBattery) return "On battery"
  if (st === "fully-charged" || (!onBattery && percentage >= 0.99)) return "Fully charged"
  return "Charging"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    statusPercent: statusPercent,
    statusState: statusState,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel
  }
}
