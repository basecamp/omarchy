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

// The watts basis: the battery device's OWN state, not the plug's claim.
// Attribution is valid whenever the battery is the power source — its
// discharge rate then IS system draw — including the marginal-adapter
// wedge where the adapter stays latched online (UPower.onBattery false)
// while the battery drains. Charging/full/pending return -1: adapter input
// is unreadable, so per-process watts are physically unattributable there.
function wattsBasis(deviceState, dischargingState, watts) {
  return deviceState === dischargingState && watts !== null && watts >= 0 ? watts : -1
}

// Kernel comm fields cap at 15 characters (TASK_COMM_LEN), so the panel's
// comm column can be sized once for the realistic worst case and never per
// sample.
// The shade lattice: three fixed opacity steps over each identity hue,
// multiplying the SAME theme color — nine distinguishable identity slots
// from three collision-free keys, zero new RGB, the 22-theme guarantee
// intact. Steps chosen against the panel's 0.12-alpha track: the lowest
// shade stays clearly above the track at panel scale (verified live).
var SHADES = [0.5, 0.75, 1.0]

var COMM_MAX_CHARS = 15

// Gap budget basis for the composition bars: the most segments any bar can
// show (top-N processes + rest + idle/available; the watts bar's base +
// top-N + else fits the same count). Callers reserve this many constant
// separators' worth of width so fills scale identically no matter how many
// segments are visible.
var SPLIT_MAX_SEGMENTS = 7

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
    buildTopProcesses: buildTopProcesses,
    buildSystemRows: buildSystemRows,
    buildSystemAnchorRow: buildSystemAnchorRow,
    buildRowImpact: buildRowImpact,
    wattsBasis: wattsBasis,
    COMM_MAX_CHARS: COMM_MAX_CHARS,
    buildResourceSplits: buildResourceSplits,
    aggregateCommShares: aggregateCommShares,
    assignColorKeys: assignColorKeys,
    stableColorKey: stableColorKey,
    stableColorHash: stableColorHash,
    SHADES: SHADES,
    slotPreferences: slotPreferences,
    resolveColorSlots: resolveColorSlots,
    SPLIT_MAX_SEGMENTS: SPLIT_MAX_SEGMENTS,
    collisionOrdinals: collisionOrdinals
  }
}

// ---- Power Hungry: top consumers ---------------------------------------------

//
// Panel-only companion to the stock battery panel: parse one sampler.sh
// snapshot and attribute the measured battery draw across processes. The bar
// pill is untouched by design — this feature answers a question you ask with
// the panel open, and the bar stays calm (see the PR's design note).

// Parses one sampler.sh snapshot into {watts, cpuTotalJiffies, cpuBusy,
// cpuTotal, memTotalKb, memAvailKb, gpuPct, processes} where processes maps
// pid -> {name, jiffies, rssKb}. watts is the absolute battery flow; the
// sampler strips the driver's discharge sign so direction comes from UPower,
// never from this value. cpuTotalJiffies is busy jiffies (the attribution
// key); cpuBusy mirrors it and cpuTotal adds idle+iowait for the system CPU%.
// mem*/gpuPct/rssKb are null/0 when their source was absent or unreadable.
function parseSnapshot(raw) {
  var watts = null
  var cpuTotalJiffies = null
  var cpuBusy = null
  var cpuTotal = null
  var memTotalKb = null
  var memAvailKb = null
  var gpuPct = null
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
    } else if (parts[0] === "cpu_busy" && parts.length >= 2 && parts[1] !== "") {
      var b = parseInt(parts[1], 10)
      if (!isNaN(b)) cpuBusy = b
    } else if (parts[0] === "cpu_total" && parts.length >= 2 && parts[1] !== "") {
      var a = parseInt(parts[1], 10)
      if (!isNaN(a)) cpuTotal = a
    } else if (parts[0] === "mem_total_kb" && parts.length >= 2 && parts[1] !== "") {
      var mt = parseInt(parts[1], 10)
      if (!isNaN(mt)) memTotalKb = mt
    } else if (parts[0] === "mem_avail_kb" && parts.length >= 2 && parts[1] !== "") {
      var ma = parseInt(parts[1], 10)
      if (!isNaN(ma)) memAvailKb = ma
    } else if (parts[0] === "gpu_pct" && parts.length >= 2 && parts[1] !== "") {
      var gp = parseInt(parts[1], 10)
      if (!isNaN(gp)) gpuPct = gp
    } else if (parts[0] === "p" && parts.length >= 4) {
      var pid = parseInt(parts[1], 10)
      var j = parseInt(parts[2], 10)
      if (!isNaN(pid) && !isNaN(j)) {
        var rss = parts.length >= 5 ? parseInt(parts[4], 10) : 0
        if (isNaN(rss)) rss = 0
        if (!(pid in processes)) processes[pid] = { name: parts[3], jiffies: j, rssKb: rss }
        else {
          if (j > processes[pid].jiffies) processes[pid].jiffies = j
          if (rss > processes[pid].rssKb) processes[pid].rssKb = rss
        }
      }
    }
  }
  return {
    watts: watts,
    cpuTotalJiffies: cpuTotalJiffies,
    cpuBusy: cpuBusy,
    cpuTotal: cpuTotal,
    memTotalKb: memTotalKb,
    memAvailKb: memAvailKb,
    gpuPct: gpuPct,
    processes: processes
  }
}

// Busiest processes by CPU share of the jiffies consumed in the window,
// aggregated by name so an app's helper processes render as one row.
//
// When the battery draw is known (discharging only — on AC the battery flow
// is charge rate, not system draw) it is split into a calibrated idle base
// and a variable slice attributed by share, so the returned rows are
// [system base, top-N..., everything else] and sum to the measured draw.
// A multi-threaded process can exceed 100% — jiffies sum across cores.
// Jiffies attributed per comm over the window, share of busy activity —
// shared by the top-process rows and the resource splits so both views are
// computed from the same numbers and can never disagree.
function aggregateCommShares(prevSnapshot, nextSnapshot, limit) {
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
  return { shares: shares.slice(0, limit || 5), all: shares, totalDelta: totalDelta }
}

function buildTopProcesses(prevSnapshot, nextSnapshot, limit, drawWatts, baseWatts) {
  var nextP = nextSnapshot.processes
  var agg = aggregateCommShares(prevSnapshot, nextSnapshot, limit)
  var shares = agg.shares

  var variable = drawWatts >= 0 ? Math.max(0, drawWatts - (baseWatts > 0 ? baseWatts : 0)) : 0
  function pct(s) { return (s >= 1 ? Math.round(s * 100) : (s * 100).toFixed(1)) + "%" }
  function wtxt(w) { return (w < 10 ? w.toFixed(1) : Math.round(w)) + " W" }
  function ramTxt(kb) {
    var mib = kb / 1024
    if (mib >= 1024) return (mib / 1024).toFixed(1) + " GiB"
    if (mib >= 1) return Math.floor(mib) + " MiB"
    return kb + " KiB"
  }

  // Current resident memory aggregated by comm — a level, not a delta, so it
  // comes from the next snapshot. RSS sums double-count pages shared between
  // processes (helpers of one app share libc etc.), which is the honest known
  // limitation of per-process memory accounting; the row is a size hint, not
  // an addition that should sum to RAM used.
  var ramByName = {}
  var anyRam = false
  for (var rpid in nextP) {
    var r = nextP[rpid].rssKb || 0
    if (r > 0) anyRam = true
    var rname = nextP[rpid].name
    if (!(rname in ramByName)) ramByName[rname] = 0
    ramByName[rname] += r
  }

  var out = []
  var topShareSum = 0
  for (var i = 0; i < shares.length; i++) {
    topShareSum += shares[i].share
    var cols = [pct(shares[i].share)]
    if (anyRam && ramByName[shares[i].label] > 0) cols.push(ramTxt(ramByName[shares[i].label]))
    if (drawWatts >= 0) cols.unshift(wtxt(variable * shares[i].share))
    out.push({ label: shares[i].label, value: cols.join(" · ") })
  }
  var otherShare = drawWatts >= 0 ? Math.max(0, 1 - topShareSum) : 0
  // One graphic line per process: each row carries metric cells (CPU, RAM,
  // W discharging only) rendered as mini-meters in fixed columns. Cells are
  // built here so QML only draws them. Normalization, per metric — ONE CPU
  // denominator everywhere: a process's CPU cell is its jiffies over ALL
  // ticks including idle (machine capacity), the same denominator as the
  // global CPU bar and the CPU composition bar, so process cells plus the
  // everything-else row sum to the global CPU% by construction. Rows still
  // rank by share of busy activity, which is the identical ordering — a
  // snapshot's busy fraction is a common factor — merely re-scaled for
  // display. RAM cell = comm RSS / MemTotal. W cell = attributed watts over
  // measured draw. Each cell's intensity ramps with its own magnitude,
  // normalized to its metric's top row (0.35 floor, 1.0 at the column max).
  function ramp(value, top) { return top > 0 ? 0.35 + 0.65 * Math.max(0, Math.min(1, value / top)) : 0.35 }
  function cellAtIntensity(metric, display, normalized, intensity) {
    return { metric: metric, value: display, normalized: Math.max(0, Math.min(1, normalized)), intensity: intensity }
  }
  function cell(metric, display, normalized, top) {
    return cellAtIntensity(metric, display, normalized, ramp(normalized, top))
  }

  var topShare = shares.length > 0 ? shares[0].share : 0
  var topRamKb = 0
  for (var rk in ramByName) if (ramByName[rk] > topRamKb) topRamKb = ramByName[rk]
  var memTotal = nextSnapshot.memTotalKb
  // busy/total fraction = the global CPU%: the scale that converts
  // share-of-work into share-of-capacity
  var totalAllDelta = prevSnapshot && nextSnapshot.cpuTotal !== null && prevSnapshot.cpuTotal !== null
    ? Math.max(0, nextSnapshot.cpuTotal - prevSnapshot.cpuTotal) : 0
  var busyFrac = totalAllDelta > 0 ? agg.totalDelta / totalAllDelta : 0
  // the W column's ramp normalizes against its largest cell, whichever row
  // owns it (usually the top process, sometimes the base floor)
  var topW = 0
  if (drawWatts >= 0) {
    if (baseWatts > 0.5) topW = Math.max(topW, baseWatts / drawWatts)
    if (shares.length > 0) topW = Math.max(topW, variable * topShare / drawWatts)
  }

  var procIdx = 0
  var cpuUsedByRows = 0
  var ramUsedByRows = 0
  for (var r = 0; r < out.length; r++) {
    var share = shares[procIdx].share
    var cpuFrac = Math.min(1, share * busyFrac)
    var ramKb = ramByName[shares[procIdx].label] !== undefined ? ramByName[shares[procIdx].label] : 0
    cpuUsedByRows += cpuFrac
    ramUsedByRows += memTotal !== null ? ramKb / memTotal : 0
    var cells = [cell("CPU", pct(cpuFrac), cpuFrac, Math.min(1, topShare * busyFrac))]
    if (memTotal !== null && ramKb > 0) cells.push(cell("RAM", ramTxt(ramKb), ramKb / memTotal, topRamKb / memTotal))
    if (drawWatts >= 0) cells.push(cell("W", wtxt(variable * share), variable * share / drawWatts, topW))
    out[r].cells = cells
    out[r].key = out[r].label
    procIdx++
  }

  // The everything-else row is a whole-machine remainder row: the CPU left
  // over after the listed processes (closing the sum to global CPU%), the
  // used RAM beyond the listed processes' RSS (clamped at zero — shared
  // pages double-counted per process can push it negative, the standing
  // disclosure), and the watts tail. It exists when ANY metric has a
  // meaningful remainder — its old existence gate was watts-only, which
  // starved the CPU/RAM closure whenever the watts tail was display noise.
  var usedFracAll = memTotal !== null && nextSnapshot.memAvailKb !== null
    ? Math.max(0, Math.min(1, 1 - nextSnapshot.memAvailKb / memTotal)) : 0
  var elseCpuRem = totalAllDelta > 0 ? Math.max(0, busyFrac - cpuUsedByRows) : 0
  var elseRamRem = memTotal !== null ? Math.max(0, usedFracAll - ramUsedByRows) : 0
  var wTail = drawWatts >= 0 ? variable * otherShare / drawWatts : 0
  if (elseCpuRem > 0.005 || elseRamRem > 0.005 || (drawWatts >= 0 && otherShare > 0.02 && variable * otherShare > 0.5)) {
    var eCells = []
    if (totalAllDelta > 0) eCells.push(cellAtIntensity("CPU", pct(elseCpuRem), elseCpuRem, 0.8))
    if (memTotal !== null) eCells.push(cellAtIntensity("RAM", ramTxt(Math.round(elseRamRem * memTotal)), elseRamRem, 0.8))
    if (drawWatts >= 0) eCells.push(cellAtIntensity("W", wtxt(variable * otherShare), wTail, 0.8))
    out.push({ label: "everything else", value: drawWatts >= 0 ? wtxt(variable * otherShare) : "", key: "else", cells: eCells })
  }

  if (drawWatts >= 0 && baseWatts > 0.5) {
    out.unshift({ label: "base load", value: wtxt(baseWatts), key: "base",
      cells: [cell("W", wtxt(baseWatts), baseWatts / drawWatts, topW)] })
  }
  return out
}

// The anchor row: the machine itself, rendered first in the process table
// with global values on the same grid and scale — CPU global%, RAM used%,
// and total draw while the watts basis is active (its W cell fills the whole
// column because the draw IS the whole the rows below decompose). The panel
// renders it in theme foreground (never literal white) so it reads as the
// neutral machine against metric-colored processes.
function buildSystemAnchorRow(prevSnapshot, nextSnapshot, drawWatts) {
  var cells = []
  if (prevSnapshot && nextSnapshot.cpuTotal !== null && prevSnapshot.cpuTotal !== null
    && nextSnapshot.cpuBusy !== null && prevSnapshot.cpuBusy !== null) {
    var totalDelta = nextSnapshot.cpuTotal - prevSnapshot.cpuTotal
    if (totalDelta > 0) {
      var g = Math.min(1, Math.max(0, (nextSnapshot.cpuBusy - prevSnapshot.cpuBusy) / totalDelta))
      cells.push({ metric: "CPU", value: Math.round(g * 100) + "%", normalized: g, intensity: 1 })
    }
  }
  if (nextSnapshot.memTotalKb !== null && nextSnapshot.memAvailKb !== null && nextSnapshot.memTotalKb > 0) {
    var used = Math.max(0, Math.min(1, 1 - nextSnapshot.memAvailKb / nextSnapshot.memTotalKb))
    cells.push({ metric: "RAM", value: Math.round(used * 100) + "%", normalized: used, intensity: 1 })
  }
  if (drawWatts >= 0) {
    cells.push({ metric: "W", value: (drawWatts < 10 ? drawWatts.toFixed(1) : Math.round(drawWatts)) + " W", normalized: 1, intensity: 1 })
  }
  if (cells.length === 0) return null
  return { label: "system", key: "system", value: "", cells: cells }
}

// ---- Power Hungry: system vitals rows ----------------------------------------

// One row per vital as {label, value, meter}, in fixed order: CPU, RAM, GPU,
// Draw. meter is 0..1 for the panel's progress-bar idiom, or -1 when the row
// has no meter to draw (a dash, or a value that is not a fraction). CPU%
// needs two snapshots (busy-delta over all-ticks-delta, idle included);
// before a second snapshot exists it shows the stock "—" placeholder rather
// than a number, matching how the stats section renders unknowns. RAM% comes
// from MemAvailable/MemTotal. GPU% appears only when the sampler found a
// user-readable utilization source — absence is the honest state on GPUs that
// expose none (e.g. Asahi), so no row is invented. Draw appears only while
// discharging with known watts, mirroring the attribution's watts rule: on
// AC the battery flow is charge rate, not system draw, and the row is omitted
// entirely instead of showing a bogus number. Draw's meter is draw/40 capped
// at 1 so the panel's green (<20 W) / yellow (<40 W) / red (beyond)
// thresholds land at 0.5 and 1.0 of the bar.
function buildSystemRows(prevSnapshot, nextSnapshot, drawWatts) {
  function wtxt(w) { return (w < 10 ? w.toFixed(1) : Math.round(w)) + " W" }
  var rows = []

  var cpuText = "—"
  var cpuMeter = -1
  if (prevSnapshot && nextSnapshot.cpuBusy !== null && nextSnapshot.cpuTotal !== null
    && prevSnapshot.cpuBusy !== null && prevSnapshot.cpuTotal !== null) {
    var totalDelta = nextSnapshot.cpuTotal - prevSnapshot.cpuTotal
    if (totalDelta > 0) {
      var busyDelta = Math.max(0, nextSnapshot.cpuBusy - prevSnapshot.cpuBusy)
      cpuMeter = Math.min(1, busyDelta / totalDelta)
      cpuText = Math.round(cpuMeter * 100) + "%"
    }
  }
  rows.push({ label: "CPU", value: cpuText, meter: cpuMeter })

  if (nextSnapshot.memTotalKb !== null && nextSnapshot.memAvailKb !== null
    && nextSnapshot.memTotalKb > 0) {
    // avail can exceed total only through a torn read; clamp so the row never
    // shows a negative or >100 percent.
    var used = Math.max(0, Math.min(1, 1 - nextSnapshot.memAvailKb / nextSnapshot.memTotalKb))
    rows.push({ label: "RAM", value: Math.round(used * 100) + "%", meter: used })
  }

  if (nextSnapshot.gpuPct !== null) {
    var gpu = Math.min(100, Math.max(0, nextSnapshot.gpuPct))
    rows.push({ label: "GPU", value: gpu + "%", meter: gpu / 100 })
  }

  if (drawWatts >= 0) {
    rows.push({ label: "Draw", value: wtxt(drawWatts), meter: Math.min(1, drawWatts / 40) })
  }

  return rows
}

// ---- Power Hungry: impact meters and resource splits -------------------------

// Per-row impact fractions for the POWER HUNGRY rows. Process rows use the
// share that ranks them — CPU share on external power, and while discharging
// the attributed watts hold the same proportion (W_i = variable × share_i by
// construction), so one fraction stays consistent with both the pct and the
// watt number the row displays. The base and tail rows meter their slice of
// the whole measured draw instead, matching the watts split bar. All values
// clamp to 0..1; -1 means "no meter" (row absent).
function buildRowImpact(topShares, drawWatts, baseWatts, variableWatts, elseShare) {
  function clamp01(v) { return Math.max(0, Math.min(1, v)) }
  var top = []
  var intensity = []
  var topShare = topShares.length > 0 ? topShares[0].share : 0
  for (var i = 0; i < topShares.length; i++) {
    top.push(clamp01(topShares[i].share))
    // intensity ramp: the top row at full opacity, tail rows fading toward a
    // 0.35 floor — share-normalized so the ramp reads the same at any load
    intensity.push(topShare > 0 ? 0.35 + 0.65 * clamp01(topShares[i].share / topShare) : 0.35)
  }
  var base = drawWatts > 0 && baseWatts > 0.5 ? clamp01(baseWatts / drawWatts) : -1
  var elseMeter = drawWatts > 0 && variableWatts >= 0 ? clamp01(variableWatts * elseShare / drawWatts) : -1
  return { top: top, intensity: intensity, base: base, elseMeter: elseMeter, baseIntensity: 1, elseIntensity: 0.8 }
}

// Segment lists for the split bars, one per resource. Every list sums to 1.0
// on physical data (fuzz-tested); the one honest exception is RAM when
// per-process RSS sums exceed system used (shared pages counted per process)
// — there the rest segment clamps to 0 and the list sums above 1, which is
// the documented double-count disclosure rather than a hidden rescale.
// Segment kinds: "comm" (top processes), "rest" (other busy / other used),
// "idle" / "avail" (unused capacity — rendered as the unfilled track),
// "base" and "else" (the attribution model's floor and tail). The same comm
// carries the same key in every list so one color map serves all bars.
function buildResourceSplits(prevSnapshot, nextSnapshot, limit, drawWatts, baseWatts, palette) {
  // The identity palette: the three collision-free theme hues (see the
  // panel's palette rationale). Passed in so callers own it; defaulted so
  // the pure builder is self-contained.
  palette = palette || ["blue", "cyan", "magenta"]
  // The shade lattice assignment, resolved ONCE over the visible set — the
  // TABLE's rank order (CPU busy-share) and nothing else — and shared by the
  // table accents and every bar: one function, one visible set. Bars lay
  // their process segments out IN THAT SAME TABLE RANK ORDER, left-to-right
  // as the table reads top-to-bottom (the operator's correspondence
  // decision): a rank swap moves exactly the swapped segments — discrete,
  // meaningful motion, identity preserved by the stable lattice colors.
  // Round 9's canonical hue-major order is superseded: it existed because
  // round-8's rank-coupled GROUP order relocated whole hue blocks; with
  // per-comm lattice-colored segments that disease no longer exists. The
  // RAM bar previously ranked its own top-N by RSS — that divergence dies
  // here: it shows the table's comms with their RSS widths, the rest
  // segment absorbing any used memory the table set doesn't cover.
  var lattice = null
  function slotOf(comm) {
    if (lattice === null) lattice = resolveColorSlots(result.order, palette, SHADES)
    return lattice.assignment[comm] !== undefined
      ? lattice.assignment[comm]
      : { hue: palette[stableColorKey(comm, palette.length)], hueIdx: stableColorKey(comm, palette.length), shadeIdx: 2, shade: 1 }
  }
  function rankCommSegments(fracList) {
    var out = []
    for (var i = 0; i < fracList.length; i++)
      out.push({ key: fracList[i].key, share: fracList[i].share, kind: "comm", slot: slotOf(fracList[i].key) })
    return out
  }
  var n = limit || 5
  var result = { order: [], cpu: null, ram: null, watts: null, gpu: null }

  var agg = prevSnapshot ? aggregateCommShares(prevSnapshot, nextSnapshot, n) : null
  if (agg) result.order = agg.shares.map(function(s) { return s.label })
  // intensity-as-criticality: utilization ramps each system bar's opacity
  // from 0.45 at idle toward 1.0 at full; the watts bar is categorical
  // (green/yellow/red) and stays at full intensity.
  result.intensity = { cpu: 0.45, ram: 0.45, watts: 1, gpu: 0.45 }

  // CPU: shares of ALL ticks this window (busy + idle) so the segments,
  // including idle, sum to exactly 1.
  if (agg && prevSnapshot && nextSnapshot.cpuBusy !== null && nextSnapshot.cpuTotal !== null
    && prevSnapshot.cpuBusy !== null && prevSnapshot.cpuTotal !== null) {
    var totalDelta = nextSnapshot.cpuTotal - prevSnapshot.cpuTotal
    var busyDelta = nextSnapshot.cpuBusy - prevSnapshot.cpuBusy
    if (totalDelta > 0) {
      var commFracs = []
      var used = 0
      for (var i = 0; i < agg.shares.length; i++) {
        // share_i is of busy activity; rescale to all ticks
        var frac = agg.shares[i].share * busyDelta / totalDelta
        if (frac > 0) { commFracs.push({ key: agg.shares[i].label, share: frac }); used += frac }
      }
      var segs = rankCommSegments(commFracs)
      // thresholds would drop sub-pixel segments and break the exact sum;
      // a 0.4% segment renders sub-pixel, which is invisibility enough
      var rest = Math.max(0, busyDelta / totalDelta - used)
      segs.push({ key: "rest", label: "rest", share: rest, kind: "rest" })
      var idle = Math.max(0, 1 - used - Math.max(0, rest))
      segs.push({ key: "idle", label: "idle", share: idle, kind: "idle" })
      result.cpu = segs
      result.intensity.cpu = 0.45 + 0.55 * Math.min(1, Math.max(0, busyDelta / totalDelta))
    }
  }

  // RAM: shares of MemTotal. RSS double-counting makes the sum exceed 1 only
  // when shared pages outweigh the slack; see the doc note above.
  if (nextSnapshot.memTotalKb !== null && nextSnapshot.memAvailKb !== null && nextSnapshot.memTotalKb > 0) {
    var totalKb = nextSnapshot.memTotalKb
    var usedFrac = Math.max(0, Math.min(1, 1 - nextSnapshot.memAvailKb / totalKb))
    var ramAll = {}
    for (var pid in nextSnapshot.processes) {
      var p = nextSnapshot.processes[pid]
      if (!p.rssKb) continue
      if (!(p.name in ramAll)) ramAll[p.name] = 0
      ramAll[p.name] += p.rssKb
    }
    // table-order RAM segments: the table's comms, in the table's rank,
    // widths = each comm's RSS share of MemTotal
    var ramFracs = []
    var rused = 0
    if (agg) {
      for (var j = 0; j < agg.shares.length; j++) {
        var nm2 = agg.shares[j].label
        if (ramAll[nm2] !== undefined && ramAll[nm2] > 0) {
          var rf = ramAll[nm2] / totalKb
          ramFracs.push({ key: nm2, share: rf })
          rused += rf
        }
      }
    }
    var rsegs = rankCommSegments(ramFracs)
    var rrest = Math.max(0, usedFrac - rused)
    rsegs.push({ key: "rest", label: "rest", share: rrest, kind: "rest" })
    rsegs.push({ key: "avail", label: "available", share: Math.max(0, 1 - usedFrac), kind: "avail" })
    result.ram = rsegs
    result.intensity.ram = 0.45 + 0.55 * usedFrac
  }

  // Watts: the attribution model as a bar — base floor, top processes, tail.
  // Present only while discharging; on AC the battery flow is charge rate,
  // not system draw, and the bar is omitted rather than faked.
  if (drawWatts >= 0 && agg) {
    var variable = Math.max(0, drawWatts - (baseWatts > 0 ? baseWatts : 0))
    var wsegs = []
    var wused = 0
    if (baseWatts > 0.5) {
      var bf = Math.min(1, baseWatts / drawWatts)
      wsegs.push({ key: "base", label: "base load", share: bf, kind: "base" })
      wused += bf
    }
    var wFracs = []
    for (var k = 0; k < agg.shares.length; k++) {
      var wf = variable * agg.shares[k].share / drawWatts
      if (wf > 0) { wFracs.push({ key: agg.shares[k].label, share: wf }); wused += wf }
    }
    wsegs = wsegs.concat(rankCommSegments(wFracs))
    var welse = Math.max(0, 1 - wused)
    wsegs.push({ key: "else", label: "everything else", share: welse, kind: "else" })
    result.watts = wsegs
  }

  // GPU: a one-value split; absent sources stay null (absence by design).
  if (nextSnapshot.gpuPct !== null) {
    var g = Math.min(100, Math.max(0, nextSnapshot.gpuPct)) / 100
    result.gpu = [
      { key: "gpu", label: "GPU", share: g, kind: "comm" },
      { key: "gpu-rest", label: "rest", share: 1 - g, kind: "rest" }
    ]
    result.intensity.gpu = 0.45 + 0.55 * g
  }

  if (lattice === null) lattice = resolveColorSlots(result.order, palette, SHADES)
  result.lattice = lattice
  return result
}

// Stable identity colors: FNV-1a over the comm name, reduced into the
// palette. Deterministic across calls, sessions, and machines — no
// randomness, no seed state, no order dependence — so a process keeps its
// hue everywhere and forever: table label accents, composition-bar groups,
// any surface. The multiply stays under 2^53 and the >>>0 fold makes the
// uint32 overflow explicit, so every QML JS engine agrees bit-for-bit.
function stableColorHash(comm) {
  var h = 2166136261
  var s = String(comm)
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = (h * 16777619) >>> 0
  }
  return h >>> 0
}

function stableColorKey(comm, paletteSize) {
  return stableColorHash(comm) % (paletteSize || 3)
}

// Full 9-slot preference ordering, derived deterministically from ONE hash:
// hue = h % 3 (low bits), shade = floor(h / 3) % 3 (the next bits —
// decorrelated from the hue bits, tested). The preferred slot comes first;
// then the SAME hue's other shades (cyclically from the preferred shade —
// hue identity survives displacement, only the shade yields); then the
// other hues in cyclic order from the preferred hue, each with shades
// cyclically from the preferred shade. Same comm, same list, forever.
function slotPreferences(comm, palette, shades) {
  palette = palette || ["blue", "cyan", "magenta"]
  shades = shades || SHADES
  var h = stableColorHash(comm)
  var hue = h % palette.length
  var shade = Math.floor(h / palette.length) % shades.length
  var prefs = [{ hue: hue, shade: shade }]
  for (var s = 1; s < shades.length; s++) prefs.push({ hue: hue, shade: (shade + s) % shades.length })
  for (var hu = 1; hu < palette.length; hu++) {
    for (var s2 = 0; s2 < shades.length; s2++)
      prefs.push({ hue: (hue + hu) % palette.length, shade: (shade + s2) % shades.length })
  }
  return prefs
}

// Claim resolution over the visible set: a pure function of the rank-ordered
// comm list — same list, same assignment, always. Claims are processed in
// claim-strength order (rank first, name lexicographic as the tiebreak), and
// each comm takes the first slot on its preference list not already taken.
// Greedy-by-strength IS the displacement fixed point in a single pass — a
// stronger claim never moves after taking a slot, so cascades cannot arise
// and termination is structural (one pass, at most nine slots). A comm with
// no free slot on any of its nine preferences is UNASSIGNED — the table
// falls back to the round-9 ordinal badge for exactly those.
// Stability contract: an uncontested comm keeps its hash slot forever;
// a contested comm's displacement is deterministic (top ranks most stable,
// shade yields before hue).
function resolveColorSlots(comms, palette, shades) {
  palette = palette || ["blue", "cyan", "magenta"]
  shades = shades || SHADES
  var ranked = comms.slice().sort(function(a, b) {
    var ia = comms.indexOf(a), ib = comms.indexOf(b)
    if (ia !== ib) return ia - ib
    return a < b ? -1 : (a > b ? 1 : 0)
  })
  var taken = {}
  var assignment = {}
  var unassigned = []
  for (var i = 0; i < ranked.length; i++) {
    var prefs = slotPreferences(ranked[i], palette, shades)
    var placed = false
    for (var p = 0; p < prefs.length; p++) {
      var key = prefs[p].hue + "-" + prefs[p].shade
      if (!taken[key]) {
        taken[key] = ranked[i]
        assignment[ranked[i]] = { hue: palette[prefs[p].hue], hueIdx: prefs[p].hue, shadeIdx: prefs[p].shade, shade: shades[prefs[p].shade] }
        placed = true
        break
      }
    }
    if (!placed) unassigned.push(ranked[i])
  }
  return { assignment: assignment, unassigned: unassigned }
}

// comm → palette-entry map, hash-derived (the old order-based assignment is
// retired: rank shuffles used to swap colors, which taught nothing). Same
// signature as before, so call sites are unchanged.
function assignColorKeys(comms, palette) {
  var map = {}
  for (var i = 0; i < comms.length; i++) map[comms[i]] = palette[stableColorKey(comms[i], palette.length)]
  return map
}

// Ordinal badges for simultaneous same-hue rows: within the visible set,
// the first member of a hue stays clean and later members get 2, 3, ... by
// rank order. The hue is identity; the badge only breaks simultaneous ties,
// so a lone member of a hue never carries a badge.
function collisionOrdinals(comms, palette) {
  var seen = {}
  var out = {}
  for (var i = 0; i < comms.length; i++) {
    var k = stableColorKey(comms[i], palette.length)
    seen[k] = (seen[k] || 0) + 1
    out[comms[i]] = seen[k] > 1 ? seen[k] : 0
  }
  return out
}
