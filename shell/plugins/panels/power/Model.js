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
// Identity is POSITIONAL, not chromatic (grayscale-by-load, operator
// decision 2026-08-29): the system block leads in white, process blocks
// follow biggest-to-lightest, and ink brightness carries magnitude. The
// hash below remains exported for potential non-color reuse.
var COMM_MAX_CHARS = 15

// Gap budget basis for the composition bars: the most segments any bar can
// show (top-N processes + the idle/available frame; the watts bar's system
// block + top-N fits under the same count). Callers reserve this many
// constant separators' worth of width so fills scale identically no matter
// how many segments are visible.
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
    wattsBasis: wattsBasis,
    COMM_MAX_CHARS: COMM_MAX_CHARS,
    buildResourceSplits: buildResourceSplits,
    aggregateCommShares: aggregateCommShares,
    stableColorKey: stableColorKey,
    stableColorHash: stableColorHash,
    SPLIT_MAX_SEGMENTS: SPLIT_MAX_SEGMENTS
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
// [system, top-N...] and sum to the measured draw. Jiffies attributed per
// comm over the window, share of busy activity — shared by the top-process
// rows and the resource splits so both views are computed from the same
// numbers and can never disagree.
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
  for (var rpid in nextP) {
    var r = nextP[rpid].rssKb || 0
    var rname = nextP[rpid].name
    if (!(rname in ramByName)) ramByName[rname] = 0
    ramByName[rname] += r
  }

  var out = []
  var topShareSum = 0
  for (var i = 0; i < shares.length; i++) {
    topShareSum += shares[i].share
    out.push({ label: shares[i].label })
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
  // the W column's ramp normalizes against the top process's cell; the
  // system row below anchors at full intensity and does not contend
  var topW = 0
  if (drawWatts >= 0 && shares.length > 0) topW = variable * topShare / drawWatts

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

  // The system row: everything not attributed to a listed process — one row,
  // first in the table (the operator review folded the old "base load" and
  // "everything else" rows into it; a separate floor row read as a mystery
  // second "system"). Its cells are the remainders on the same grid and
  // scale as the processes: the CPU left over after the listed processes
  // (closing the sum to global CPU%), the used RAM beyond the listed
  // processes' RSS (clamped at zero — shared pages double-counted per
  // process can push it negative, the standing disclosure), and the watts
  // the model does not attribute (the calibrated idle floor PLUS the
  // variable tail). System + top processes = the whole on every metric,
  // exactly — that sum is the one-reality invariant. Cells anchor at full
  // intensity; the panel renders the row in theme foreground so it reads as
  // the neutral machine against metric-colored processes.
  var usedFracAll = memTotal !== null && nextSnapshot.memAvailKb !== null
    ? Math.max(0, Math.min(1, 1 - nextSnapshot.memAvailKb / memTotal)) : 0
  var sysCpuRem = totalAllDelta > 0 ? Math.max(0, busyFrac - cpuUsedByRows) : 0
  var sysRamRem = memTotal !== null ? Math.max(0, usedFracAll - ramUsedByRows) : 0
  var sysCells = []
  if (totalAllDelta > 0) sysCells.push(cellAtIntensity("CPU", pct(sysCpuRem), sysCpuRem, 1))
  if (memTotal !== null) sysCells.push(cellAtIntensity("RAM", ramTxt(Math.round(sysRamRem * memTotal)), sysRamRem, 1))
  if (drawWatts >= 0) {
    var sysW = (baseWatts > 0 ? baseWatts : 0) + variable * otherShare
    sysCells.push(cellAtIntensity("W", wtxt(sysW), sysW / drawWatts, 1))
  }
  if (sysCells.length > 0) out.unshift({ label: "system", key: "system", cells: sysCells })
  return out
}

// ---- Power Hungry: system vitals rows ----------------------------------------

// One row per vital as {label, value, meter}, in fixed order: CPU, RAM, GPU.
// meter is 0..1 for the panel's progress-bar idiom, or -1 when the row
// has no meter to draw (a dash, or a value that is not a fraction). CPU%
// needs two snapshots (busy-delta over all-ticks-delta, idle included);
// before a second snapshot exists it shows the stock "—" placeholder rather
// than a number, matching how the stats section renders unknowns. RAM% comes
// from MemAvailable/MemTotal. GPU% appears only when the sampler found a
// user-readable utilization source — absence is the honest state on GPUs that
// expose none (e.g. Asahi), so no row is invented. There is deliberately no
// Draw row: total system draw is the stock pill's own number and the stats
// section's rate row (same sampler telemetry), and the attribution below
// decomposes it — a third copy was duplication, removed in operator review.
function buildSystemRows(prevSnapshot, nextSnapshot) {
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

  return rows
}

// ---- Power Hungry: resource splits --------------------------------------------

// Segment lists for the split bars, one per resource. Every list sums to 1.0
// on physical data (fuzz-tested); the one honest exception is RAM when
// per-process RSS sums exceed system used (shared pages counted per process)
// — there the rest segment clamps to 0 and the list sums above 1, which is
// the documented double-count disclosure rather than a hidden rescale.
// Segment kinds: "comm" (top processes), "system" (everything unattributed
// — leads every bar, mirroring the table's system row), "rest" (the GPU
// bar's non-GPU remainder), "idle" / "avail" (unused capacity — rendered as
// the unfilled track). The same comm carries the same key in every list so
// one color map serves all bars.
function buildResourceSplits(prevSnapshot, nextSnapshot, limit, drawWatts, baseWatts) {
  // Segment ink is the PANEL's concern (foreground at load-scaled opacity);
  // this builder owns membership and order: a SYSTEM block leads — the
  // table's system row made spatial — then process blocks size-descending
  // by the bar's own metric, then the idle/available frame.
  // Ink follows load (operator decision 2026-08-29): segments carry no
  // color — the panel paints every comm in foreground at a load-scaled
  // opacity. Bars are self-sorted visualizations: a SYSTEM block leads —
  // the table's system row made spatial, in full ink — then process
  // blocks size-descending by the bar's own metric, then the idle/
  // available frame. The TABLE keeps the single shared rank; per-bar
  // order may differ from it and between bars by design.
  function rankCommSegments(fracList) {
    var out = []
    for (var i = 0; i < fracList.length; i++)
      out.push({ key: fracList[i].key, share: fracList[i].share, kind: "comm" })
    return out
  }
  var n = limit || 5
  var result = { order: [], cpu: null, ram: null, watts: null, gpu: null }

  var agg = prevSnapshot ? aggregateCommShares(prevSnapshot, nextSnapshot, n) : null
  if (agg) result.order = agg.shares.map(function(s) { return s.label })
  // intensity-as-criticality: utilization ramps each system bar's opacity
  // from 0.45 at idle toward 1.0 at full; the watts bar has no utilization
  // ramp (draw is not a fraction of a capacity) and stays at full intensity.
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
      // SYSTEM block first: unattributed busy, the anchor made spatial
      var segs = [{ key: "system", label: "system", share: Math.max(0, busyDelta / totalDelta - used), kind: "system" }]
      segs = segs.concat(rankCommSegments(commFracs))
      var idle = Math.max(0, 1 - used - Math.max(0, busyDelta / totalDelta - used))
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
    // the table's comms with their RSS widths, self-sorted size-descending
    // (the RAM bar sorts by RSS even though the table ranks by CPU — bars
    // are self-sorted visualizations)
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
    ramFracs.sort(function(a, b) { return b.share - a.share })
    var rsegs = [{ key: "system", label: "system", share: Math.max(0, usedFrac - rused), kind: "system" }]
    rsegs = rsegs.concat(rankCommSegments(ramFracs))
    rsegs.push({ key: "avail", label: "available", share: Math.max(0, 1 - usedFrac), kind: "avail" })
    result.ram = rsegs
    result.intensity.ram = 0.45 + 0.55 * usedFrac
  }

  // Watts: the attribution model as a bar — the system block (everything
  // unattributed: the calibrated idle floor plus the variable tail) first,
  // then the top processes in their table colors, biggest to lightest.
  // Present only while discharging; on AC the battery flow is charge rate,
  // not system draw, and the bar is omitted rather than faked.
  if (drawWatts >= 0 && agg) {
    var variable = Math.max(0, drawWatts - (baseWatts > 0 ? baseWatts : 0))
    var wused = 0
    var wFracs = []
    for (var k = 0; k < agg.shares.length; k++) {
      var wf = variable * agg.shares[k].share / drawWatts
      if (wf > 0) { wFracs.push({ key: agg.shares[k].label, share: wf }); wused += wf }
    }
    var wsegs = [{ key: "system", label: "system", share: Math.max(0, 1 - wused), kind: "system" }]
    wsegs = wsegs.concat(rankCommSegments(wFracs))
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

// Stable identity colors: FNV-1a over the comm name, reduced into the
// palette. Deterministic across calls, sessions, and machines — no
// randomness, no seed state, no order dependence — so a process keeps its
// hue everywhere and forever: the table row's mark, composition-bar
// segments, any surface. (Hues can collide — three palette keys, five rows —
// and that is accepted by the operator-review color rule: the table is the
// single color authority, identity is name→hue, and a displaced hue would
// break the table↔bar correspondence the lattice was retired for.) The
// multiply stays under 2^53 and the >>>0 fold makes the uint32 overflow
// explicit, so every QML JS engine agrees bit-for-bit.
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
