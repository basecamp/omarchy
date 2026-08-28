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

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

// A device is a physical battery when UPower types it as one, it is a power
// supply (rules out battery-powered peripherals — mice, headsets, controllers)
// and it carries a native path. The display pseudo-device also types itself as
// a battery, so it is excluded by identity and by its empty native path.
function isPhysicalBattery(device, displayDevice, types) {
  var d = device || {}
  var t = types || {}
  if (!d || d === displayDevice) return false
  if (d.type !== t.Battery) return false
  if (d.powerSupply === false) return false
  return String(d.nativePath || "") !== ""
}

function physicalBatteries(devices, displayDevice, types) {
  var list = []
  var values = devices || []
  for (var i = 0; i < values.length; i++) {
    if (isPhysicalBattery(values[i], displayDevice, types))
      list.push(values[i])
  }
  list.sort(function(a, b) {
    return String(a.nativePath).localeCompare(String(b.nativePath))
  })
  return list
}

// Parses the plugin's bin/battery-details output: <native-path>\t<key>\t<value>
// per line, into { BAT0: { cycles: "964", ... }, BAT1: {...} }.
function parseBatteryDetails(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 3) continue
    var name = parts[0].trim()
    var key = parts[1].trim()
    if (!name || !key) continue
    if (!out[name]) out[name] = {}
    out[name][key] = parts.slice(2).join("\t").trim()
  }
  return out
}

function deviceStateLabel(device, states) {
  var d = device || {}
  var s = states || {}
  if (!d.isPresent) return "Absent"
  if (d.state === s.Charging) return "Charging"
  if (d.state === s.Discharging) return "Discharging"
  if (d.state === s.Empty) return "Empty"
  if (d.state === s.FullyCharged) return "Full"
  if (d.state === s.PendingCharge) return "Holding"
  if (d.state === s.PendingDischarge) return "Pending"
  return "Idle"
}

// Watts flowing through one cell. UPower reports changeRate unsigned, so the
// sign has to come from the state.
function deviceRateLabel(device, states) {
  var d = device || {}
  var rate = Math.abs(Number(d.changeRate || 0))
  if (!d.isPresent || rate < 0.05) return "—"
  var sign = d.state === (states || {}).Discharging ? "-" : "+"
  return sign + (rate < 10 ? rate.toFixed(1) : Math.round(rate)) + "W"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    isPhysicalBattery: isPhysicalBattery,
    physicalBatteries: physicalBatteries,
    parseBatteryDetails: parseBatteryDetails,
    deviceStateLabel: deviceStateLabel,
    deviceRateLabel: deviceRateLabel
  }
}
