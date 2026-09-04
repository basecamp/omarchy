import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Shared telemetry singleton for the task manager. The shell mounts one of
// these per session and hands the same instance to the bar widget (via
// `bar.shell.serviceFor`) and to the summoned overlay (injected as `service`),
// so both surfaces read one sampler and one history rather than starting a
// second /proc walk each.
Item {
  id: root

  // The plugin's internal id. Public labels say "Task Manager"; everything the
  // machine reads — this id, the IPC target, the layer-shell namespace, the
  // state directory — says omatask, matching Quattro's Omawrite/Omacut family.
  readonly property string pluginId: "omarchy.omatask"

  // Injected by the shell's service loader.
  property var shell: null
  property var manifest: ({})
  property string omarchyPath: ""

  // Tunables. The bar widget owns the shell.json entry, so it pushes these in
  // rather than the service re-reading config the widget already parsed.
  property int intervalSec: 2
  property int historyPoints: 60
  property int processLimit: 60

  readonly property string sourceDir: (manifest && manifest.__sourceDir) ? String(manifest.__sourceDir) : ""
  readonly property bool samplerAvailable: sourceDir !== ""

  // ------------------------------------------------------------- live state

  property var latest: ({})
  property bool ready: false
  property string lastError: ""

  property var cpuHistory: []
  property var memHistory: []
  property var netRxHistory: []
  property var netTxHistory: []
  property var gpuHistory: []
  property var gpuEncodeHistory: []
  property var gpuDecodeHistory: []
  // Temperature rings are filled on every sample, not just while a thermal
  // view is open, because both readings are on the free path — a CPU die
  // register and an NVML query. That is what lets the graphs open showing the
  // last two minutes instead of starting flat.
  property var cpuTempHistory: []
  property var gpuTempHistory: []
  property var memStallHistory: []
  // All three come out of the meminfo parse we already do, so they cost
  // nothing and can be collected always — which is what lets the memory
  // breakdown open with real history instead of an empty canvas.
  property var memAnonHistory: []
  property var memCacheHistory: []
  property var swapUsedHistory: []
  // /proc/net/wireless costs 0.012ms, so signal strength is collected always
  // and its graph opens populated like the temperature ones.
  property var wifiSignalHistory: []
  property var diskUtilHistory: []
  property var diskReadHistory: []
  property var diskWriteHistory: []
  // One history ring per logical core, for the expanded per-core view. Kept
  // unconditionally: the alternative is starting every expand from an empty
  // graph, and 32 rings of 60 floats costs nothing worth measuring.
  property var coreHistories: []

  readonly property var cpu: latest.cpu || ({})
  readonly property var mem: latest.mem || ({})
  readonly property var net: latest.net || ({})
  readonly property var disk: latest.disk || ({})
  readonly property var gpu: latest.gpu || ({})

  readonly property var gpuDevices: gpu.devices || []
  readonly property bool hasGpu: gpuDevices.length > 0
  readonly property var primaryGpu: hasGpu ? gpuDevices[0] : ({})
  readonly property real gpuPercent: Number(primaryGpu.util) || 0
  readonly property real gpuMemUsed: Number(primaryGpu.memUsed) || 0
  readonly property real gpuMemTotal: Number(primaryGpu.memTotal) || 0
  readonly property real gpuMemPercent: gpuMemTotal > 0 ? (gpuMemUsed / gpuMemTotal) * 100 : 0
  readonly property var gpuProcesses: primaryGpu.procs || []
  // Engine counters are null on a driver or card that cannot report them, and
  // the UI hides those rows rather than drawing a permanent zero.
  readonly property bool hasGpuEngines: primaryGpu.encode !== undefined && primaryGpu.encode !== null

  // Threads for the one expanded process, empty when nothing is expanded.
  readonly property int threadsOf: Number(latest.threadsOf) || 0
  readonly property var threads: latest.threads || []

  readonly property real cpuPercent: Number(cpu.total) || 0
  readonly property var cores: cpu.cores || []
  readonly property int coreCount: Number(cpu.count) || 0
  readonly property var loadAverage: cpu.load || [0, 0, 0]

  readonly property real memTotal: Number(mem.total) || 0
  readonly property real memUsed: Number(mem.used) || 0
  readonly property real memPercent: memTotal > 0 ? (memUsed / memTotal) * 100 : 0
  readonly property real swapTotal: Number(mem.swapTotal) || 0
  readonly property real swapUsed: Number(mem.swapUsed) || 0
  readonly property real swapPercent: swapTotal > 0 ? (swapUsed / swapTotal) * 100 : 0

  // ---------------------------------------------------------- memory detail
  readonly property var pressure: latest.pressure || ({})
  readonly property var memPressure: pressure.memory || ({})
  readonly property var cpuPressure: pressure.cpu || ({})
  readonly property var ioPressure: pressure.io || ({})
  readonly property bool hasPressure: pressure.memory !== undefined
  // `some avg10`: the share of the last ten seconds in which at least one task
  // stalled waiting for memory. Unlike a usage percentage, anything above zero
  // is a real symptom.
  readonly property real memStall: Number(memPressure.some10) || 0

  readonly property var swaps: latest.swaps || []

  // ------------------------------------------------------ preferences
  //
  // A preference is a choice about how you like the tool; transient state is
  // what you happen to be doing right now. The first should survive a shell
  // restart, the second should not — a filter or a selection that came back
  // after an update would be a bug, not a feature.
  //
  // shell.json is the store, so preferences live in the same place as every
  // other Omarchy setting and remain editable by hand or through
  // Setup > Plugins. The bar widget owns that entry and hands its contents
  // here, because the overlay has no route to it.

  property var widgetSettings: ({})

  // Writing a value that equals the shipped default only adds noise to
  // shell.json — every fresh install would immediately gain keys nobody set.
  // These must match manifest.json's defaults.
  readonly property var preferenceDefaults: ({
    "groupApps": true,
    "listMode": "processes",
    "sortBy": "cpu",
    "sortDescending": true
  })

  function persist(key, value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return
    if (widgetSettings[key] === value) return      // nothing to write
    var isDefault = preferenceDefaults[key] === value
    if (isDefault && widgetSettings[key] === undefined) return   // never set
    var next = {}
    for (var k in widgetSettings) next[k] = widgetSettings[k]
    if (isDefault) delete next[key]      // back at the default: drop the key
    else next[key] = value
    widgetSettings = next
    shell.updateEntryInline(pluginId, next)
  }

  // ---------------------------------------------------- applications
  //
  // Omarchy launches every app into its own systemd scope, so the kernel is
  // already grouping processes the way a person thinks about them. These are
  // whole applications — one Chromium, not forty-seven chromium processes —
  // and `mem` is the honest figure rather than a sum of double-counted RSS.
  readonly property var apps: latest.apps || []
  readonly property bool ioDelegated: latest.ioDelegated === true
  readonly property var userApps: apps.filter(function(a) { return !a.system })
  readonly property var systemApps: apps.filter(function(a) { return a.system })

  property bool appsDetail: false
  onAppsDetailChanged: send("apps " + (appsDetail ? "on" : "off"))

  // One row per application, or one row per systemd scope. Grouping is right
  // nearly always; turning it off is how you see that Chromium is actually two
  // scopes, or check what a merged row is made of.
  property bool groupApps: true
  onGroupAppsChanged: {
    send("groupapps " + (groupApps ? "on" : "off"))
    persist("groupApps", groupApps)
  }

  // Which list the overlay opens on, and how it is ordered. Held by the
  // service rather than the overlay because the overlay is destroyed every
  // time it closes, and a preference that dies with the window is not one.
  property string listMode: "processes"
  onListModeChanged: persist("listMode", listMode)

  property string sortBy: "cpu"
  onSortByChanged: persist("sortBy", sortBy)

  property bool sortDescending: true
  onSortDescendingChanged: persist("sortDescending", sortDescending)

  // ---------------------------------------------------- health & hardware
  readonly property var cpuFreq: latest.cpufreq || ({})
  readonly property var coreFreqs: cpuFreq.cores || []
  readonly property real peakFreq: {
    var peak = 0
    for (var i = 0; i < coreFreqs.length; i++) peak = Math.max(peak, coreFreqs[i])
    return peak
  }
  readonly property var irq: latest.irq || ({})
  readonly property var btrfs: latest.btrfs || []
  readonly property var failedUnits: latest.failedUnits || []

  // Softirq skew worth reporting. A handful of times is normal scheduling; a
  // hundred-fold means one core is carrying an interrupt line alone.
  readonly property var irqWarnings: {
    var out = []
    for (var key in irq) {
      var entry = irq[key]
      if (entry && entry.imbalance && entry.imbalance >= 20) {
        out.push({ name: key, imbalance: entry.imbalance, core: entry.busiestCore })
      }
    }
    return out
  }

  // ---------------------------------------------------- sockets & files
  readonly property var socketCounts: latest.socketCounts || ({})
  readonly property var openFiles: latest.openFiles || null

  property bool socketDetail: false
  onSocketDetailChanged: send("sockets " + (socketDetail ? "on" : "off"))

  property int openFilesPid: 0
  onOpenFilesPidChanged: send("openfiles " + (openFilesPid > 0 ? openFilesPid : "off"))

  // ---------------------------------------------------- recorded history
  //
  // Replayed from disk once per session so the graphs open with whatever was
  // recorded before this shell started, rather than from an empty canvas.
  property var recorded: []
  readonly property bool hasRecorded: recorded.length > 0

  function requestHistory() { send("history") }

  // ------------------------------------------------------------ network
  readonly property var netLinks: net.links || []
  readonly property var netInterfaces: net.ifaces || []
  readonly property var sockets: latest.sockets || ({})
  readonly property var wifiLink: {
    for (var i = 0; i < netLinks.length; i++) {
      if (netLinks[i].wireless) return netLinks[i]
    }
    return null
  }
  readonly property bool hasWifi: wifiLink !== null
  // Rounded dBm. -30 is next to the router, -90 is unusable.
  readonly property real wifiSignal: hasWifi ? Number(wifiLink.wireless.signal) || 0 : 0

  // Rate for one interface, so the link rows can show their own throughput
  // rather than only the machine-wide total.
  function rateFor(name) {
    for (var i = 0; i < netInterfaces.length; i++) {
      if (netInterfaces[i].name === name) return netInterfaces[i]
    }
    return { rx: 0, tx: 0 }
  }

  // ------------------------------------------------------------- disk
  readonly property var diskDevices: disk.devices || []
  readonly property var filesystems: disk.filesystems || []
  readonly property var ioProcesses: latest.ioProcs || []
  readonly property int ioReadable: Number(latest.ioReadable) || 0
  readonly property int ioTotal: Number(latest.ioTotal) || 0
  // Busiest device's utilisation, for the headline graph.
  readonly property real diskUtil: {
    var peak = 0
    for (var i = 0; i < diskDevices.length; i++) {
      peak = Math.max(peak, Number(diskDevices[i].util) || 0)
    }
    return peak
  }
  // Drive temperatures arrive through hwmon, which knows nothing about block
  // devices, so the sampler resolves each chip to the devices it speaks for and
  // sends them along. Matching on that, rather than on the first sensor that
  // happens to say "composite", is what stops a second drive from reporting the
  // first one's temperature.
  function tempForDevice(name) {
    var wanted = String(name)
    var fallback = null
    for (var i = 0; i < driveSensors.length; i++) {
      var sensor = driveSensors[i]
      var owned = sensor.devices || []
      if (owned.indexOf(wanted) === -1) continue
      // An NVMe chip reports Composite alongside per-die sensors; Composite is
      // the one that means "this drive". The others run hotter and are parts.
      if (String(sensor.label).toLowerCase().indexOf("composite") !== -1) return sensor.temp
      if (fallback === null) fallback = sensor.temp
    }
    return fallback
  }

  property bool diskDetail: false
  onDiskDetailChanged: send("diskdetail " + (diskDetail ? "on" : "off"))

  property bool netDetail: false
  onNetDetailChanged: send("netdetail " + (netDetail ? "on" : "off"))
  readonly property real committed: Number(mem.committed) || 0
  readonly property real commitLimit: Number(mem.commitLimit) || 0
  readonly property bool overcommitted: commitLimit > 0 && committed > commitLimit

  // The breakdown behind "used", largest first. Page cache is deliberately
  // excluded: it is not used memory in any sense a user cares about.
  readonly property var memBreakdown: {
    if (!mem.total) return []
    var parts = [
      { label: "Processes", key: "anon", value: Number(mem.anon) || 0 },
      { label: "Shared / tmpfs", key: "shmem", value: Number(mem.shmem) || 0 },
      { label: "Kernel slab (reclaimable)", key: "slabRecl", value: Number(mem.slabReclaimable) || 0 },
      { label: "Kernel slab (locked)", key: "slabUnrecl", value: Number(mem.slabUnreclaimable) || 0 },
      { label: "Page tables", key: "pageTables", value: Number(mem.pageTables) || 0 },
      { label: "Kernel stacks", key: "kernelStack", value: Number(mem.kernelStack) || 0 }
    ]
    return parts.filter(function(p) { return p.value > 0 })
  }

  // --------------------------------------------------------------- thermals
  readonly property var thermal: latest.thermal || ({})
  readonly property var sensors: thermal.sensors || []
  readonly property var fans: thermal.fans || []
  // False means the board exposes no tachometer at all — a different thing
  // from fans that are genuinely stopped, and worth saying out loud.
  readonly property bool fansAvailable: thermal.fansAvailable === true
  readonly property bool hasCpuTemp: thermal.cpu !== undefined && thermal.cpu !== null
  readonly property real cpuTemp: Number(thermal.cpu) || 0

  // The sampler tags each sensor with a coarse kind, so a surface can ask for
  // the DIMM sensors without re-deriving which hwmon chip names mean memory.
  function sensorsOfKind(kind) {
    return (sensors || []).filter(function(s) { return s.kind === kind })
  }
  readonly property var dimmSensors: sensorsOfKind("dimm")
  readonly property var driveSensors: sensorsOfKind("drive")

  // The off-CPU sensors each cost a bus transaction, so they follow the same
  // rule as PCIe: measured only while a view is listing them.
  property bool sensorDetail: false
  onSensorDetailChanged: send("sensors " + (sensorDetail ? "on" : "off"))

  readonly property real uptime: Number(latest.uptime) || 0
  readonly property var processes: latest.procs || []
  readonly property int processCount: Number(latest.procCount) || 0
  readonly property int runningCount: Number(latest.procRunning) || 0
  readonly property int threadCount: Number(latest.threadCount) || 0

  // ------------------------------------------- process-table subscriptions
  //
  // Walking every /proc/<pid> is the expensive half of a sample, and it is
  // wasted while the only thing on screen is a bar sparkline. Surfaces that
  // show processes retain the table for as long as they are open; the sampler
  // stops building it when the last one lets go.

  property int _processHolders: 0
  readonly property bool processesActive: _processHolders > 0

  function retainProcesses() {
    _processHolders = _processHolders + 1
  }

  function releaseProcesses() {
    _processHolders = Math.max(0, _processHolders - 1)
  }

  onProcessesActiveChanged: {
    send("procs " + (processesActive ? "on" : "off"))
    // The table is stale the moment we stop collecting it. Clearing avoids a
    // reopened panel showing whatever the CPU ordering was minutes ago.
    if (!processesActive && latest.procs) {
      var next = {}
      for (var key in latest) next[key] = latest[key]
      delete next.procs
      latest = next
    }
  }

  onIntervalSecChanged: send("interval " + intervalSec)
  onProcessLimitChanged: send("limit " + processLimit)

  // ------------------------------------------------- thread subscription
  //
  // Only one process can be expanded at a time, so this is a plain pid rather
  // than a refcount: whoever expands last owns the thread view.

  // PCIe throughput and per-client VRAM are only rendered in the expanded GPU
  // card, and NVML charges ~20ms per PCIe counter, so they follow the same
  // "measure it while something shows it" rule as the process table.
  // Nothing displays GPU data at idle, and mapping the NVIDIA driver costs
  // ~31MB of RSS, so the sampler only loads it while a GPU-showing surface is
  // open. Retained rather than a plain flag: both the panel and the overlay
  // can want it at once.
  property int _gpuHolders: 0
  readonly property bool gpuWanted: _gpuHolders > 0
  function retainGpu() { _gpuHolders = _gpuHolders + 1 }
  function releaseGpu() { _gpuHolders = Math.max(0, _gpuHolders - 1) }
  onGpuWantedChanged: send("gpu " + (gpuWanted ? "on" : "off"))

  property bool gpuDetail: false

  onGpuDetailChanged: send("gpudetail " + (gpuDetail ? "on" : "off"))

  property int threadPid: 0

  function watchThreads(pid) {
    threadPid = Number(pid) || 0
  }

  function unwatchThreads(pid) {
    // Ignore a stale collapse from a row that is no longer the expanded one.
    if (pid === undefined || Number(pid) === threadPid) threadPid = 0
  }

  onThreadPidChanged: {
    send("threads " + (threadPid > 0 ? threadPid : "off"))
    if (threadPid <= 0 && latest.threads) {
      var next = {}
      for (var key in latest) next[key] = latest[key]
      delete next.threads
      delete next.threadsOf
      latest = next
    }
  }

  onHistoryPointsChanged: {
    cpuHistory = Model.pushHistory(cpuHistory, cpuPercent, historyPoints)
    memHistory = Model.pushHistory(memHistory, memPercent, historyPoints)
  }

  // ------------------------------------------------------------- ingestion

  function ingest(line) {
    var text = String(line || "").trim()
    if (text === "") return

    var data
    try {
      data = JSON.parse(text)
    } catch (error) {
      // Without a piece of the offending line this says only that parsing
      // failed, which is the one thing already obvious from the error.
      var snippet = String(text).slice(0, 120)
      if (String(text).length > 120) snippet += "…"
      lastError = "unparseable sample: " + error + " — " + snippet
      return
    }

    // The history replay is a one-shot answer on the same stream, not a sample.
    if (data.history !== undefined) {
      recorded = data.history || []
      return
    }

    latest = data
    ready = true
    lastError = ""

    var sampledMem = data.mem || {}
    var memTotalBytes = Number(sampledMem.total) || 0
    cpuHistory = Model.pushHistory(cpuHistory, data.cpu ? data.cpu.total : 0, historyPoints)
    memHistory = Model.pushHistory(memHistory,
      memTotalBytes > 0 ? (Number(sampledMem.used) / memTotalBytes) * 100 : 0, historyPoints)
    netRxHistory = Model.pushHistory(netRxHistory, data.net ? data.net.rx : 0, historyPoints)
    netTxHistory = Model.pushHistory(netTxHistory, data.net ? data.net.tx : 0, historyPoints)

    var sampledGpus = data.gpu ? (data.gpu.devices || []) : []
    if (sampledGpus.length > 0) {
      gpuHistory = Model.pushHistory(gpuHistory, sampledGpus[0].util, historyPoints)
      gpuEncodeHistory = Model.pushHistory(gpuEncodeHistory, sampledGpus[0].encode || 0, historyPoints)
      gpuDecodeHistory = Model.pushHistory(gpuDecodeHistory, sampledGpus[0].decode || 0, historyPoints)
      if (sampledGpus[0].temp !== null && sampledGpus[0].temp !== undefined) {
        gpuTempHistory = Model.pushHistory(gpuTempHistory, sampledGpus[0].temp, historyPoints)
      }
    }

    // Only pushed when a reading actually arrived: a gap would otherwise be
    // recorded as 0°C and draw a cliff to the floor of the graph.
    var thermal = data.thermal || {}
    if (thermal.cpu !== null && thermal.cpu !== undefined) {
      cpuTempHistory = Model.pushHistory(cpuTempHistory, thermal.cpu, historyPoints)
    }

    memAnonHistory = Model.pushHistory(memAnonHistory, Number(sampledMem.anon) || 0, historyPoints)
    memCacheHistory = Model.pushHistory(memCacheHistory, Number(sampledMem.cached) || 0, historyPoints)
    swapUsedHistory = Model.pushHistory(swapUsedHistory, Number(sampledMem.swapUsed) || 0, historyPoints)

    var sampledDisks = (data.disk || {}).devices || []
    var busiest = 0
    for (var di = 0; di < sampledDisks.length; di++) {
      busiest = Math.max(busiest, Number(sampledDisks[di].util) || 0)
    }
    diskUtilHistory = Model.pushHistory(diskUtilHistory, busiest, historyPoints)
    diskReadHistory = Model.pushHistory(diskReadHistory, (data.disk || {}).read || 0, historyPoints)
    diskWriteHistory = Model.pushHistory(diskWriteHistory, (data.disk || {}).write || 0, historyPoints)

    var links = (data.net || {}).links || []
    for (var li = 0; li < links.length; li++) {
      if (links[li].wireless) {
        wifiSignalHistory = Model.pushHistory(wifiSignalHistory, links[li].wireless.signal, historyPoints)
        break
      }
    }

    var memoryPressure = (data.pressure || {}).memory
    if (memoryPressure) {
      memStallHistory = Model.pushHistory(memStallHistory, memoryPressure.some10 || 0, historyPoints)
    }

    evaluateAlerts()

    coreHistories = Model.pushCoreHistories(coreHistories,
      data.cpu ? data.cpu.cores : [], historyPoints)
  }

  function send(command) {
    if (!sampler.running) return
    sampler.write(command + "\n")
  }

  // ------------------------------------------------------------- processes

  // SIGTERM asks; SIGKILL insists. The panel offers TERM on click and KILL
  // only behind a confirm, matching what every other task manager does.
  function killProcess(pid, signal) {
    var target = Number(pid)
    if (!(target > 0)) return
    var name = String(signal || "TERM").toUpperCase()
    if (["TERM", "KILL", "INT", "HUP", "STOP", "CONT", "USR1", "USR2"].indexOf(name) === -1) return
    killer.command = ["kill", "-" + name, String(target)]
    killer.running = true
  }

  // Nice presets, matching the vocabulary a person uses rather than the
  // kernel's -20..19 scale. Values follow the convention Resources settled on.
  readonly property var nicePresets: [
    { label: "Very high", nice: -19 },
    { label: "High",      nice: -5 },
    { label: "Normal",    nice: 0 },
    { label: "Low",       nice: 5 },
    { label: "Very low",  nice: 19 }
  ]

  function niceLabel(value) {
    var n = Number(value)
    if (n <= -8) return "Very high"
    if (n <= -3) return "High"
    if (n <= 2) return "Normal"
    if (n <= 6) return "Low"
    return "Very low"
  }

  // Lowering niceness needs privilege; raising it does not. Try unprivileged
  // first and only escalate when the kernel actually refuses, so the common
  // case never shows an authentication dialog.
  function setPriority(pid, nice) {
    var target = Number(pid)
    if (!(target > 0)) return
    var value = Math.max(-20, Math.min(19, Math.round(Number(nice) || 0)))
    priorityAction.command = ["sh", "-c",
      "renice -n " + value + " -p " + target + " >/dev/null 2>&1 || " +
      "pkexec renice -n " + value + " -p " + target]
    priorityAction.running = true
  }

  // A comma-separated CPU list, e.g. "0-7,16". taskset applies to the whole
  // process; threads created afterwards inherit it.
  function setAffinity(pid, cpuList) {
    var target = Number(pid)
    if (!(target > 0)) return
    var list = String(cpuList || "").replace(/[^0-9,\-]/g, "")
    if (list === "") return
    affinityAction.command = ["taskset", "-a", "-pc", list, String(target)]
    affinityAction.running = true
  }

  Process {
    id: priorityAction
    stderr: SplitParser { onRead: function(line) { root.lastError = String(line) } }
  }

  Process {
    id: affinityAction
    stderr: SplitParser { onRead: function(line) { root.lastError = String(line) } }
  }

  // ------------------------------------------------------------- alerts
  //
  // A monitor you have to be looking at is a monitor that misses things, and
  // the shell hosting this plugin already owns a notification daemon.

  // Off until asked for. A monitor that starts pushing desktop notifications
  // the moment it is installed is making a decision that belongs to the person
  // running it — and the conditions it alarms on (a full disk, a hot CPU) are
  // often already known and deliberate.
  property bool alertsEnabled: false
  property var _alerted: ({})

  function alert(key, summary, body, urgent) {
    if (!alertsEnabled || _alerted[key]) return
    // Latch per condition: a disk that is full stays full, and a notification
    // every two seconds would be worse than none.
    var next = {}
    for (var k in _alerted) next[k] = _alerted[k]
    next[key] = true
    _alerted = next

    notifier.command = ["notify-send", "-a", "Task Manager",
                        "-u", urgent ? "critical" : "normal",
                        summary, body]
    notifier.running = true
  }

  function clearAlert(key) {
    if (!_alerted[key]) return
    var next = {}
    for (var k in _alerted) if (k !== key) next[k] = _alerted[k]
    _alerted = next
  }

  Process { id: notifier }

  // Conditions worth interrupting someone for. Each latches on the way up and
  // clears on the way down, so a flapping value does not spam.
  function evaluateAlerts() {
    if (!ready) return

    for (var i = 0; i < filesystems.length; i++) {
      var fs = filesystems[i]
      var key = "fs:" + fs.device
      if (Number(fs.percent) >= 95) {
        alert(key, "Filesystem almost full",
              fs.mounts.join(", ") + " is " + Math.round(fs.percent) + "% full — "
              + Model.formatBytes(fs.avail) + " left", true)
      } else if (Number(fs.percent) < 90) {
        clearAlert(key)
      }
    }

    if (memStall >= 10) {
      alert("mem-stall", "Memory pressure",
            "Tasks are stalling on memory (" + memStall.toFixed(1) + "% of the last 10s)", true)
    } else if (memStall < 2) {
      clearAlert("mem-stall")
    }

    if (hasCpuTemp && cpuTemp >= 95) {
      alert("cpu-temp", "CPU at thermal limit",
            Math.round(cpuTemp) + "°C — the CPU is likely throttling", true)
    } else if (hasCpuTemp && cpuTemp < 88) {
      clearAlert("cpu-temp")
    }

    for (var d = 0; d < btrfs.length; d++) {
      var meta = (btrfs[d].allocation || {}).metadata
      if (meta && Number(meta.percent) >= 95) {
        alert("btrfs-meta:" + btrfs[d].label, "btrfs metadata nearly full",
              btrfs[d].label + " metadata is " + Math.round(meta.percent)
              + "% used — this is how btrfs runs out of space", true)
      }
      if (Number(btrfs[d].errors) > 0) {
        alert("btrfs-err:" + btrfs[d].label, "btrfs device errors",
              btrfs[d].label + " has logged " + btrfs[d].errors + " device error(s)", true)
      }
    }

    if (failedUnits.length > 0) {
      alert("units:" + failedUnits.length, "systemd units failed",
            failedUnits.map(function(u) { return u.unit }).join(", "), false)
    } else {
      // Keys carry the count, so clear every latch once nothing is failing.
      for (var k in _alerted) {
        if (k.indexOf("units:") === 0) clearAlert(k)
      }
    }
  }

  Process {
    id: killer
    // A kill that fails (already exited, not ours) is normal and not worth a
    // dialog — the row simply disappears or does not, on the next sample.
    stderr: SplitParser { onRead: function(line) { root.lastError = String(line) } }
  }

  // --------------------------------------------------------------- sampler

  Process {
    id: sampler
    running: root.samplerAvailable
    // No tunables in argv: interval, limit, and the process toggle all change
    // over stdin, so adjusting a setting never restarts the sampler and never
    // interrupts the history.
    command: ["python3", root.sourceDir + "/sampler.py"]
    stdinEnabled: true

    onStarted: {
      root.send("interval " + root.intervalSec)
      root.send("limit " + root.processLimit)
      root.send("procs " + (root.processesActive ? "on" : "off"))
      root.send("gpudetail " + (root.gpuDetail ? "on" : "off"))
      root.send("sensors " + (root.sensorDetail ? "on" : "off"))
      root.send("netdetail " + (root.netDetail ? "on" : "off"))
      root.send("diskdetail " + (root.diskDetail ? "on" : "off"))
      root.send("apps " + (root.appsDetail ? "on" : "off"))
      root.send("groupapps " + (root.groupApps ? "on" : "off"))
      root.send("sockets " + (root.socketDetail ? "on" : "off"))
      root.send("gpu " + (root.gpuWanted ? "on" : "off"))
      root.requestHistory()
      if (root.threadPid > 0) root.send("threads " + root.threadPid)
    }

    stdout: SplitParser { onRead: function(line) { root.ingest(line) } }
    stderr: SplitParser { onRead: function(line) { root.lastError = String(line) } }

    // A sampler that dies (python upgrade mid-session, OOM kill) would
    // otherwise leave every surface frozen on its last frame with no hint why.
    onExited: function(exitCode) {
      root.ready = false
      if (root.samplerAvailable) {
        if (exitCode !== 0) root.lastError = "sampler exited with code " + exitCode
        restart.restart()
      }
    }
  }

  Timer {
    id: restart
    interval: 3000
    onTriggered: if (root.samplerAvailable && !sampler.running) sampler.running = true
  }
}
