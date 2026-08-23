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

function deviceList(devices) {
  if (!devices) return []
  if (Array.isArray(devices)) return devices
  if (devices.values) return devices.values
  return []
}

function packPathKey(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : ""
}

function pathsMatch(a, b) {
  var ka = packPathKey(a)
  var kb = packPathKey(b)
  if (!ka || !kb) return false
  return ka === kb
}

function laptopDevices(devices) {
  var list = deviceList(devices)
  var packs = []
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    if (!device || !device.isPresent) continue
    if (device.isLaptopBattery === false) continue
    var path = String(device.nativePath || "")
    if (!path || path === "DisplayDevice") continue
    packs.push(device)
  }
  return packs
}

// Same liveness test as bin/omarchy-battery-status pack_is_live: a healthy
// empty cell still shows voltage, while a present-but-dead pack is 0 V / 0 Wh.
// Quickshell's UPowerDevice may omit voltage; the CLI then supplies pack.N.path.
function isLivePack(device) {
  if (!device || !device.isPresent) return false
  if (Number(device.energy || 0) > 0.05) return true
  if (Math.abs(Number(device.changeRate || 0)) > 0.05) return true
  if (Number(device.percentage || 0) > 0) return true
  if (Number(device.voltage || 0) > 0.5) return true
  return false
}

function selectedPackPaths(info) {
  var kv = info || {}
  var paths = []
  for (var i = 0; i < 16; i++) {
    var path = kv["pack." + i + ".path"]
    if (path === undefined || path === "") break
    paths.push(String(path))
  }
  return paths
}

function liveLaptopDevices(devices, statusInfo) {
  var packs = laptopDevices(devices)
  var selected = selectedPackPaths(statusInfo)
  if (selected.length > 0) {
    var matched = []
    for (var j = 0; j < packs.length; j++) {
      var nativePath = String(packs[j].nativePath || "")
      for (var i = 0; i < selected.length; i++) {
        if (pathsMatch(nativePath, selected[i])) {
          matched.push(packs[j])
          break
        }
      }
    }
    if (matched.length > 0) return matched
  }

  var live = []
  for (var k = 0; k < packs.length; k++) {
    if (isLivePack(packs[k])) live.push(packs[k])
  }
  return live.length > 0 ? live : packs
}

function packsEnergyFraction(packs) {
  if (!packs || packs.length === 0) return -1

  var now = 0
  var full = 0
  for (var i = 0; i < packs.length; i++) {
    now += Number(packs[i].energy || 0)
    full += Number(packs[i].energyCapacity || 0)
  }
  if (full > 0) return Math.max(0, Math.min(1, now / full))
  return batteryFraction(packs[0])
}

function combinedEnergyFraction(devices, statusInfo) {
  return packsEnergyFraction(liveLaptopDevices(devices, statusInfo))
}

function combinedFractionFromStatus(info) {
  var raw = info && info.percentage
  if (raw === undefined || raw === "") return -1
  var value = parseFloat(String(raw).replace("%", ""))
  if (isNaN(value)) return -1
  return Math.max(0, Math.min(1, value / 100))
}

function parseWh(raw) {
  var value = parseFloat(String(raw || "").replace(/Wh$/i, ""))
  return isNaN(value) ? -1 : value
}

function parseWatts(raw) {
  var value = parseFloat(String(raw || "").replace(/W$/i, ""))
  return isNaN(value) ? 0 : value
}

function formatHoursJs(hours) {
  if (!(hours > 0)) return ""
  if (hours * 60 < 60) return Math.max(1, Math.floor(hours * 60)) + "m"
  var whole = Math.floor(hours)
  var minutes = Math.floor((hours - whole) * 60)
  if (minutes > 0) return whole + "h " + minutes + "m"
  return whole + "h"
}

function formatWhJs(wh) {
  var rounded = Math.round(wh * 10) / 10
  if (Math.abs(rounded - Math.round(rounded)) < 0.05) return String(Math.round(rounded))
  return String(rounded)
}

// Reject EC fuel-gauge cliffs (e.g. 37% → 6% in a minute) that exceed what
// the measured wattage could have moved. Reset on charge/discharge flips so
// a real plug-in is not stuck on the pre-cliff value.
function applyEnergySample(previous, next, nowMs) {
  var sample = next || {}
  var energy = parseWh(sample.energy)
  var full = parseWh(sample.size)
  var rate = parseWatts(sample.rate)
  var prev = previous || {}
  var prevEnergy = parseWh(prev.energy)
  var prevRate = parseWatts(prev.rate)
  var prevMs = Number(prev._sampleMs || 0)
  var dt = prevMs > 0 ? (Number(nowMs) - prevMs) / 1000 : 0
  var state = sample.state || ""
  var prevState = prev.state || ""

  if (energy >= 0 && prevEnergy >= 0 && dt > 0 && dt < 120) {
    var flipped = (state === "charging" && prevState !== "charging") ||
      (state === "discharging" && prevState !== "discharging")
    if (!flipped && energy < prevEnergy) {
      var maxDrop = Math.abs(prevRate) * (dt / 3600) * 3 + 0.5
      if (prevEnergy - energy > maxDrop) energy = prevEnergy
    }
  }

  var out = {}
  var key
  for (key in sample) {
    if (Object.prototype.hasOwnProperty.call(sample, key)) out[key] = sample[key]
  }
  if (energy >= 0) {
    out.energy = formatWhJs(energy) + "Wh"
    if (full > 0) {
      out.percentage = String(Math.round(Math.max(0, Math.min(1, energy / full)) * 100)) + "%"
      if (Math.abs(rate) > 0.2) {
        if (state === "charging") out.time = formatHoursJs((full - energy) / Math.abs(rate))
        else if (state === "discharging") out.time = formatHoursJs(energy / Math.abs(rate))
      }
    }
  }
  out._sampleMs = String(nowMs)
  return out
}

// Combine live packs into a watt-hour sample, reject EC cliffs against
// `previous`, and return the fraction warn and critical-action must use.
function liveEnergySnapshot(devices, statusInfo, previous, nowMs, states) {
  var packs = liveLaptopDevices(devices, statusInfo)
  if (!packs || packs.length === 0) {
    return { sample: previous || {}, fraction: -1, discharging: false }
  }

  var now = 0
  var full = 0
  var rate = 0
  var discharging = false
  var charging = false
  var s = states || {}
  var chargingState = s.Charging !== undefined ? s.Charging : "charging"
  var dischargingState = s.Discharging !== undefined ? s.Discharging : "discharging"
  var i

  for (i = 0; i < packs.length; i++) {
    now += Number(packs[i].energy || 0)
    full += Number(packs[i].energyCapacity || 0)
    rate += Number(packs[i].changeRate || 0)
    if (packs[i].state === chargingState) charging = true
    if (packs[i].state === dischargingState) discharging = true
  }

  var stateName = "unknown"
  if (charging) stateName = "charging"
  else if (discharging) stateName = "discharging"

  var rateAbs = rate < 0 ? -rate : rate
  var sample = {
    energy: formatWhJs(now) + "Wh",
    size: formatWhJs(full) + "Wh",
    rate: formatWhJs(rateAbs) + "W",
    state: stateName
  }
  var smoothed = applyEnergySample(previous, sample, nowMs)
  return {
    sample: smoothed,
    fraction: combinedFractionFromStatus(smoothed),
    discharging: discharging && !charging
  }
}

function viewDevice(devices, fallback, states, statusInfo) {
  var packs = liveLaptopDevices(devices, statusInfo)
  if (packs.length === 0) return fallback || {}
  if (packs.length === 1) {
    var only = packs[0]
    return {
      isPresent: true,
      percentage: packsEnergyFraction(packs),
      state: only.state,
      changeRate: only.changeRate,
      timeToFull: only.timeToFull,
      energy: only.energy,
      energyCapacity: only.energyCapacity
    }
  }

  var s = states || {}
  var changeRate = 0
  var state = packs[0].state
  var charging = false
  var discharging = false
  for (var i = 0; i < packs.length; i++) {
    changeRate += Number(packs[i].changeRate || 0)
    if (packs[i].state === s.Charging && Number(packs[i].changeRate || 0) > 0.2) charging = true
    if (packs[i].state === s.Discharging) discharging = true
  }
  if (charging) state = s.Charging
  else if (discharging) state = s.Discharging

  return {
    isPresent: true,
    percentage: packsEnergyFraction(packs),
    state: state,
    changeRate: changeRate,
    timeToFull: 0,
    energy: 0,
    energyCapacity: 0
  }
}

function anyPackCharging(devices, states, statusInfo) {
  var packs = liveLaptopDevices(devices, statusInfo)
  var s = states || {}
  for (var i = 0; i < packs.length; i++) {
    if (packs[i].state === s.Charging && Number(packs[i].changeRate || 0) > 0.2) return true
  }
  return false
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

  // A slow charge into a second pack can take well over eight hours. Only
  // treat the pack as holding when current has actually stalled.
  return Number(d.changeRate || 0) <= 0.2
}

function chargeThresholdActiveForPacks(devices, onBattery, states, statusInfo) {
  if (onBattery) return false
  if (anyPackCharging(devices, states, statusInfo)) return false
  if (statusInfo && statusInfo.state === "holding") return true
  if (statusInfo && (statusInfo.state === "charging" || statusInfo.state === "discharging")) return false

  var packs = liveLaptopDevices(devices, statusInfo)
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

function modeLabel(device, onBattery, states, thresholdOverride) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  var threshold = thresholdOverride !== undefined ? !!thresholdOverride : chargeThresholdActive(d, onBattery, states)
  if (threshold) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
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
    laptopDevices: laptopDevices,
    isLivePack: isLivePack,
    packPathKey: packPathKey,
    pathsMatch: pathsMatch,
    selectedPackPaths: selectedPackPaths,
    liveLaptopDevices: liveLaptopDevices,
    packsEnergyFraction: packsEnergyFraction,
    combinedEnergyFraction: combinedEnergyFraction,
    combinedFractionFromStatus: combinedFractionFromStatus,
    parseWh: parseWh,
    applyEnergySample: applyEnergySample,
    liveEnergySnapshot: liveEnergySnapshot,
    viewDevice: viewDevice,
    anyPackCharging: anyPackCharging,
    chargeThresholdActive: chargeThresholdActive,
    chargeThresholdActiveForPacks: chargeThresholdActiveForPacks,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel
  }
}
