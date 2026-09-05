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
    parseSnapshot: parseSnapshot,
    buildTopProcesses: buildTopProcesses
  }
}

// ---- Power Hungry: top consumers ---------------------------------------------
//
// Panel-only companion to the stock battery panel: parse one sampler.sh
// snapshot and attribute the measured battery draw across processes. The bar
// pill is untouched by design — this feature answers a question you ask with
// the panel open, and the bar stays calm (see the PR's design note).

// Parses one sampler.sh snapshot into {watts, cpuTotalJiffies, processes}
// where processes maps pid -> {name, jiffies}. watts is the absolute battery
// flow; the sampler strips the driver's discharge sign so direction comes
// from UPower, never from this value.
function parseSnapshot(raw) {
  var watts = null
  var cpuTotalJiffies = null
  var processes = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] === "watts" && parts.length >= 2 && parts[1] !== "") {
      var w = parseFloat(parts[1])
      if (!isNaN(w)) watts = w
    } else if (parts[0] === "cputotal" && parts.length >= 2 && parts[1] !== "") {
      var t = parseInt(parts[1], 10)
      if (!isNaN(t)) cpuTotalJiffies = t
    } else if (parts[0] === "p" && parts.length >= 4) {
      var pid = parseInt(parts[1], 10)
      var j = parseInt(parts[2], 10)
      if (!isNaN(pid) && !isNaN(j)) {
        if (!(pid in processes)) processes[pid] = { name: parts[3], jiffies: j }
        else if (j > processes[pid].jiffies) processes[pid].jiffies = j
      }
    }
  }
  return { watts: watts, cpuTotalJiffies: cpuTotalJiffies, processes: processes }
}

// Busiest processes by CPU share of the jiffies consumed in the window,
// aggregated by name so an app's helper processes render as one row.
//
// When the battery draw is known (discharging only — on AC the battery flow
// is charge rate, not system draw) it is split into a calibrated idle base
// and a variable slice attributed by share, so the returned rows are
// [system base, top-N..., everything else] and sum to the measured draw.
// A multi-threaded process can exceed 100% — jiffies sum across cores.
function buildTopProcesses(prevSnapshot, nextSnapshot, limit, drawWatts, baseWatts) {
  var nextP = nextSnapshot.processes
  var prevP = prevSnapshot ? prevSnapshot.processes : {}
  var totalDelta = Math.max(1,
    nextSnapshot.cpuTotalJiffies - (prevSnapshot ? prevSnapshot.cpuTotalJiffies : 0))

  var byName = {}
  for (var pid in nextP) {
    var prev = prevP[pid]
    if (prev === undefined) continue
    var delta = nextP[pid].jiffies - prev.jiffies
    if (delta <= 0) continue
    if (!(nextP[pid].name in byName)) byName[nextP[pid].name] = 0
    byName[nextP[pid].name] += delta
  }
  var shares = []
  for (var name in byName) shares.push({ label: name, share: byName[name] / totalDelta })
  shares.sort(function(a, b) { return b.share - a.share })
  shares = shares.slice(0, limit || 5)

  var variable = drawWatts >= 0 ? Math.max(0, drawWatts - (baseWatts > 0 ? baseWatts : 0)) : 0
  function pct(s) { return (s >= 1 ? Math.round(s * 100) : (s * 100).toFixed(1)) + "%" }
  function wtxt(w) { return (w < 10 ? w.toFixed(1) : Math.round(w)) + " W" }

  var out = []
  var topShareSum = 0
  for (var i = 0; i < shares.length; i++) {
    topShareSum += shares[i].share
    out.push({
      label: shares[i].label,
      value: drawWatts >= 0 ? wtxt(variable * shares[i].share) + " (" + pct(shares[i].share) + ")" : pct(shares[i].share)
    })
  }
  if (drawWatts >= 0) {
    if (baseWatts > 0.5) out.unshift({ label: "system base", value: wtxt(baseWatts) })
    var otherShare = Math.max(0, 1 - topShareSum)
    if (otherShare > 0.02 && variable * otherShare > 0.5)
      out.push({ label: "everything else", value: wtxt(variable * otherShare) })
  }
  return out
}
