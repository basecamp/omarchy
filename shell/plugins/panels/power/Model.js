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

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

// The band a configured charge limit holds the pack in, as 0..1 fractions, or
// null when no real limit is configured. The threshold string is the one
// omarchy-battery-status prints: "75-80%" for a start/end pair, "80%" when only
// one value is known. An end of 100% is sysfs reporting no limit at all, and a
// start of 0 is "no start threshold" rather than "holds from empty".
function chargeHoldBand(threshold) {
  var match = /(\d+)\s*(?:-\s*(\d+))?\s*%/.exec(String(threshold || ""))
  if (!match) return null

  var end = Number(match[2] !== undefined ? match[2] : match[1])
  if (end >= 100) return null

  var start = Number(match[1])
  return { floor: (start > 0 ? start : end) / 100, end: end / 100 }
}

function chargeHoldFloor(threshold) {
  var band = chargeHoldBand(threshold)
  return band ? band.floor : -1
}

function chargeThresholdActive(device, onBattery, states, threshold) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false

  // Each branch below reads a stopped or stalled charge as a deliberate hold,
  // and none of them can be one without a limit configured to do the holding: a
  // failed pack, an insufficient supply and charge_behaviour=inhibit-charge stop
  // the charge just as flatly. omarchy-battery-status gates the same three cases
  // on the same limit, and the panel has to agree with the line it prints.
  var band = chargeHoldBand(threshold)
  if (!band) return false

  // PendingCharge is only "AC is present and the EC is not charging", so the
  // level has to have reached the band before the limit explains it.
  if (d.state === s.PendingCharge) return fraction >= band.floor

  // A healthy pack reports FullyCharged at the top of whatever band it is held
  // in; stopping short of full is the limit doing its job.
  if (d.state === s.FullyCharged) return fraction < 0.99

  if (d.state !== s.Charging || fraction >= 0.99) return false

  // A charge that crawls below the limit is a slow charge, not a hold.
  if (fraction < band.end) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states, threshold) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var holding = chargeThresholdActive(d, onBattery, states, threshold)

  if (holding) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states, threshold) {
  var d = device || {}
  var s = states || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states, threshold)) return "Threshold"
  if (onBattery) return "On battery"
  // A worn pack reports FullyCharged short of 100%. The percentage alone
  // cannot see that, and the icon already reads the state, so the label has
  // to as well or the two disagree on the same battery.
  if (d.state === s.FullyCharged || percentage >= 1) return "Fully charged"
  return "Charging"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeHoldBand: chargeHoldBand,
    chargeHoldFloor: chargeHoldFloor,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel
  }
}
