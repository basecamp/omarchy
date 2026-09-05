// Which outputs count as the machine's own panel. Same test the monitor
// helpers in bin/ use, so "internal" means the same thing across the system.
var INTERNAL = /^(eDP|LVDS|DSI)/i

function isInternal(name) {
  return !!name && INTERNAL.test(name)
}

// The rates an output advertises at the resolution it is already using.
// Restricting to the current mode means a rate change can never also change
// the resolution behind the user's back.
function ratesFor(monitor) {
  if (!monitor || !monitor.availableModes) return []
  var prefix = monitor.width + "x" + monitor.height + "@"
  var seen = ({})
  var rates = []
  for (var i = 0; i < monitor.availableModes.length; i++) {
    var mode = monitor.availableModes[i]
    if (mode.indexOf(prefix) !== 0) continue
    var rate = mode.substring(prefix.length).replace(/Hz$/, "")
    if (seen[rate]) continue
    seen[rate] = true
    rates.push(rate)
  }
  rates.sort(function (a, b) { return parseFloat(a) - parseFloat(b) })
  return rates
}

// On mains with charge to spare, run the panel as fast as it goes. Otherwise
// run it as slow as it goes. Being on mains is the hard requirement: on
// battery the frugal rate applies at any charge. A battery that cannot be read
// only relaxes the threshold, so a laptop with a dead gauge still runs fast
// while plugged in rather than being pinned low forever.
function targetRate(monitor, onBattery, percent, threshold) {
  var rates = ratesFor(monitor)
  if (rates.length < 2) return ""
  var readable = typeof percent === "number" && percent >= 0
  var charged = readable ? percent >= threshold : true
  return (!onBattery && charged) ? rates[rates.length - 1] : rates[0]
}

// Hyprland reports 165.02000 for the mode written as 165.02, so compare on the
// rounded value rather than the string.
function needsChange(monitor, rate) {
  if (!rate || !monitor) return false
  return Math.round(Number(monitor.refreshRate)) !== Math.round(parseFloat(rate))
}

function monitorSpec(monitor, rate) {
  if (!monitor || !rate) return ""
  if (!/^[A-Za-z0-9._-]+$/.test(monitor.name)) return ""
  return 'hl.monitor({ output = "' + monitor.name + '", mode = "' +
    monitor.width + "x" + monitor.height + "@" + rate +
    '", position = "' + monitor.x + "x" + monitor.y +
    '", scale = ' + monitor.scale + " })"
}

// Every internal output that is on the wrong rate, as ready-to-eval specs.
function pendingSpecs(monitors, onBattery, percent, threshold) {
  var specs = []
  if (!monitors) return specs
  for (var i = 0; i < monitors.length; i++) {
    var monitor = monitors[i]
    if (!monitor || monitor.disabled === true || !isInternal(monitor.name)) continue
    var rate = targetRate(monitor, onBattery, percent, threshold)
    if (!needsChange(monitor, rate)) continue
    var spec = monitorSpec(monitor, rate)
    if (spec) specs.push(spec)
  }
  return specs
}

if (typeof module !== "undefined") {
  module.exports = {
    isInternal: isInternal,
    ratesFor: ratesFor,
    targetRate: targetRate,
    needsChange: needsChange,
    monitorSpec: monitorSpec,
    pendingSpecs: pendingSpecs
  }
}
