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
    buildTopProcesses: buildTopProcesses,
    buildSystemRows: buildSystemRows,
    buildRowImpact: buildRowImpact,
    buildResourceSplits: buildResourceSplits,
    aggregateCommShares: aggregateCommShares,
    assignColorKeys: assignColorKeys
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
  if (drawWatts >= 0) {
    if (baseWatts > 0.5) out.unshift({ label: "system base", value: wtxt(baseWatts), key: "base" })
    if (otherShare > 0.02 && variable * otherShare > 0.5)
      out.push({ label: "everything else", value: wtxt(variable * otherShare), key: "else" })
  }
  // One graphic line per process: each row carries metric cells (CPU, RAM,
  // W discharging only) rendered as mini-meters in fixed columns. Cells are
  // built here so QML only draws them. Normalization, per metric: CPU cell =
  // the process's CPU share clamped to the cell width (shares can exceed 1
  // across cores — the clamp is display-only, the number tells the truth);
  // RAM cell = comm RSS / MemTotal; W cell = attributed watts / measured
  // draw. Each cell's intensity ramps with its own magnitude, normalized to
  // its metric's top row (0.35 floor, 1.0 at the column's max) so the
  // strongest signal in every column reads at full strength.
  function ramp(value, top) { return top > 0 ? 0.35 + 0.65 * Math.max(0, Math.min(1, value / top)) : 0.35 }
  function cell(metric, display, normalized, top) {
    return { metric: metric, value: display, normalized: Math.max(0, Math.min(1, normalized)), intensity: ramp(normalized, top) }
  }

  var topShare = shares.length > 0 ? shares[0].share : 0
  var topRamKb = 0
  for (var rk in ramByName) if (ramByName[rk] > topRamKb) topRamKb = ramByName[rk]
  var memTotal = nextSnapshot.memTotalKb
  // the W column's ramp normalizes against its largest cell, whichever row
  // owns it (usually the top process, sometimes the base floor)
  var topW = 0
  if (drawWatts >= 0) {
    if (baseWatts > 0.5) topW = Math.max(topW, baseWatts / drawWatts)
    if (shares.length > 0) topW = Math.max(topW, variable * topShare / drawWatts)
  }

  var procIdx = 0
  for (var r = 0; r < out.length; r++) {
    if (out[r].key === "base") {
      out[r].cells = drawWatts >= 0
        ? [cell("W", wtxt(baseWatts), baseWatts / drawWatts, topW)]
        : []
      continue
    }
    if (out[r].key === "else") {
      out[r].cells = drawWatts >= 0
        ? [cell("W", wtxt(variable * otherShare), variable * otherShare / drawWatts, topW)]
        : []
      continue
    }
    var share = shares[procIdx].share
    var ramKb = ramByName[shares[procIdx].label] !== undefined ? ramByName[shares[procIdx].label] : 0
    var cells = [cell("CPU", pct(share), share, topShare)]
    if (memTotal !== null && ramKb > 0) cells.push(cell("RAM", ramTxt(ramKb), ramKb / memTotal, topRamKb / memTotal))
    if (drawWatts >= 0) cells.push(cell("W", wtxt(variable * share), variable * share / drawWatts, topW))
    out[r].cells = cells
    out[r].key = out[r].label
    procIdx++
  }
  return out
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
function buildResourceSplits(prevSnapshot, nextSnapshot, limit, drawWatts, baseWatts) {
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
      var segs = []
      var used = 0
      for (var i = 0; i < agg.shares.length; i++) {
        // share_i is of busy activity; rescale to all ticks
        var frac = agg.shares[i].share * busyDelta / totalDelta
        if (frac > 0) { segs.push({ key: agg.shares[i].label, label: agg.shares[i].label, share: frac, kind: "comm" }); used += frac }
      }
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
    var ramAll = []
    var seen = {}
    for (var pid in nextSnapshot.processes) {
      var p = nextSnapshot.processes[pid]
      if (!p.rssKb) continue
      if (!(p.name in seen)) { seen[p.name] = 0; }
      seen[p.name] += p.rssKb
    }
    var ramList = []
    for (var nm in seen) ramList.push({ label: nm, kb: seen[nm] })
    ramList.sort(function(a, b) { return b.kb - a.kb })
    ramList = ramList.slice(0, n)
    var rsegs = []
    var rused = 0
    for (var j = 0; j < ramList.length; j++) {
      var rf = ramList[j].kb / totalKb
      if (rf > 0) { rsegs.push({ key: ramList[j].label, label: ramList[j].label, share: rf, kind: "comm" }); rused += rf }
      if (result.order.indexOf(ramList[j].label) === -1) result.order.push(ramList[j].label)
    }
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
      wsegs.push({ key: "base", label: "system base", share: bf, kind: "base" })
      wused += bf
    }
    for (var k = 0; k < agg.shares.length; k++) {
      var wf = variable * agg.shares[k].share / drawWatts
      if (wf > 0) { wsegs.push({ key: agg.shares[k].label, label: agg.shares[k].label, share: wf, kind: "comm" }); wused += wf }
    }
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

  return result
}

// Deterministic comm → palette-slot map so a comm keeps one color across the
// CPU, RAM, and watts bars and its row meter. Palette cycles past its length;
// beyond the palette the collision is accepted (row order disambiguates) and
// documented — themes carry only so many distinguishable hues.
function assignColorKeys(order, palette) {
  var map = {}
  for (var i = 0; i < order.length; i++) map[order[i]] = palette[i % palette.length]
  return map
}
