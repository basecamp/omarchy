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

function parsePacks(info) {
  var kv = info || {}
  var packs = []
  for (var i = 0; i < 16; i++) {
    var prefix = "pack." + i + "."
    if (kv[prefix + "path"] === undefined && kv[prefix + "percentage"] === undefined) break
    packs.push({
      path: kv[prefix + "path"] || ("BAT" + i),
      percentage: kv[prefix + "percentage"] || "",
      state: kv[prefix + "state"] || "",
      size: kv[prefix + "size"] || "",
      rate: kv[prefix + "rate"] || "",
      cycles: kv[prefix + "cycles"] || ""
    })
  }
  return packs
}

function packSummary(pack) {
  var parts = []
  if (pack && pack.percentage) parts.push(pack.percentage)
  if (pack && pack.state) parts.push(pack.state)
  if (pack && pack.rate && pack.state === "charging") parts.push(pack.rate)
  return parts.join(" · ")
}

function combinedFractionFromStatus(info) {
  var raw = info && info.percentage
  if (raw === undefined || raw === "") return -1
  var value = parseFloat(String(raw).replace("%", ""))
  if (isNaN(value)) return -1
  return Math.max(0, Math.min(1, value / 100))
}

function laptopDevices(devices) {
  var list = Array.isArray(devices) ? devices : []
  var packs = []
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    if (!device || !device.isPresent) continue
    if (device.isLaptopBattery === false) continue
    var path = String(device.nativePath || "")
    if (path === "DisplayDevice") continue
    packs.push(device)
  }
  return packs
}

function combinedEnergyFraction(devices) {
  var packs = laptopDevices(devices)
  if (packs.length === 0) return -1

  var now = 0
  var full = 0
  for (var i = 0; i < packs.length; i++) {
    now += Number(packs[i].energy || 0)
    full += Number(packs[i].energyCapacity || 0)
  }
  if (full > 0) return Math.max(0, Math.min(1, now / full))
  return batteryFraction(packs[0])
}

function anyPackCharging(devices, states) {
  var packs = laptopDevices(devices)
  var s = states || {}
  for (var i = 0; i < packs.length; i++) {
    var device = packs[i]
    if (device.state === s.Charging && Number(device.changeRate || 0) > 0.2) return true
  }
  return false
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

  // A slow charge into a large or second pack can take well over eight hours.
  // Only treat the pack as holding when current has actually stalled.
  return Number(d.changeRate || 0) <= 0.2
}

function chargeThresholdActiveForPacks(devices, onBattery, states, statusInfo) {
  if (statusInfo && statusInfo.state === "holding") return true
  if (statusInfo && (statusInfo.state === "charging" || statusInfo.state === "discharging")) return false
  if (anyPackCharging(devices, states)) return false

  var packs = laptopDevices(devices)
  if (packs.length === 0) return chargeThresholdActive(null, onBattery, states)

  for (var i = 0; i < packs.length; i++) {
    if (!chargeThresholdActive(packs[i], onBattery, states)) return false
  }
  return true
}

function batteryIcon(device, onBattery, states, thresholdOverride) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = thresholdOverride !== undefined ? !!thresholdOverride : chargeThresholdActive(d, onBattery, states)

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

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parsePacks: parsePacks,
    packSummary: packSummary,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    combinedFractionFromStatus: combinedFractionFromStatus,
    laptopDevices: laptopDevices,
    combinedEnergyFraction: combinedEnergyFraction,
    anyPackCharging: anyPackCharging,
    chargeThresholdActive: chargeThresholdActive,
    chargeThresholdActiveForPacks: chargeThresholdActiveForPacks,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel
  }
}
