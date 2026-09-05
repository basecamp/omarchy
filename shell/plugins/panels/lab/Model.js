function defaultStatus() {
  return {
    installed: false,
    domainRunning: false,
    viewerActive: false,
    fullscreen: false,
    state: "not installed",
    display: "",
    windowWidth: 0,
    windowHeight: 0,
    zoom: 100,
    autoResize: true,
    cursor: "auto",
    audio: true,
    usbRedirection: true,
    keepInBar: false,
    aspect: ""
  }
}

function validAspect(value) {
  return ["16:9", "16:10", "3:2", "4:3", "21:9", "32:9"].indexOf(String(value || "")) !== -1
}

function parseStatus(raw) {
  var fallback = defaultStatus()
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return fallback

    var zoom = Math.floor(Number(parsed.zoom))
    return {
      installed: parsed.installed === true,
      domainRunning: parsed.domainRunning === true,
      viewerActive: parsed.viewerActive === true,
      fullscreen: parsed.fullscreen === true,
      state: typeof parsed.state === "string" && parsed.state !== "" ? parsed.state : fallback.state,
      display: /^\d+x\d+$/.test(String(parsed.display || "")) ? String(parsed.display) : "",
      windowWidth: Math.max(0, Math.floor(Number(parsed.windowWidth) || 0)),
      windowHeight: Math.max(0, Math.floor(Number(parsed.windowHeight) || 0)),
      zoom: isFinite(zoom) && zoom >= 10 && zoom <= 400 ? zoom : fallback.zoom,
      autoResize: typeof parsed.autoResize === "boolean" ? parsed.autoResize : fallback.autoResize,
      cursor: parsed.cursor === "local" ? "local" : "auto",
      audio: typeof parsed.audio === "boolean" ? parsed.audio : fallback.audio,
      usbRedirection: typeof parsed.usbRedirection === "boolean" ? parsed.usbRedirection : fallback.usbRedirection,
      keepInBar: typeof parsed.keepInBar === "boolean" ? parsed.keepInBar : fallback.keepInBar,
      aspect: validAspect(parsed.aspect) ? String(parsed.aspect) : ""
    }
  } catch (e) {
    return fallback
  }
}

function parseBarStatus(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return { viewerActive: false, keepInBar: false }
    return {
      viewerActive: parsed.viewerActive === true,
      keepInBar: parsed.keepInBar === true
    }
  } catch (e) {
    return { viewerActive: false, keepInBar: false }
  }
}

function statusText(status) {
  if (!status || !status.installed) return "Not installed"
  if (!status.domainRunning) return "Guest " + String(status.state || "stopped")
  if (!status.viewerActive) return "Guest running · viewer closed"
  if (status.display) return "Guest running · " + status.display
  return "Guest running · viewer open"
}

function parseObject(raw) {
  try {
    var value = JSON.parse(String(raw || ""))
    return value && typeof value === "object" && !Array.isArray(value) ? value : {}
  } catch (e) {
    return {}
  }
}

function parseArray(raw, key) {
  var value = parseObject(raw)
  return Array.isArray(value[key]) ? value[key] : []
}

function healthText(raw) {
  var value = parseObject(raw)
  if (!value.severity) return "Health unavailable"
  var guest = value.guest || {}
  var domain = value.domain || {}
  var failed = Array.isArray(guest.failedUnits) ? guest.failedUnits.length : Number(guest.failedUnits || 0)
  var memory = guest.memory || {}
  var memoryTotal = Number(memory.totalBytes || 0)
  var memoryAvailable = Number(memory.availableBytes || 0)
  var memoryText = memoryTotal > 0 ? Math.round((memoryTotal - memoryAvailable) / memoryTotal * 100) + "% memory" : "memory n/a"
  return String(value.severity).toUpperCase() + " · " + String(domain.ip || "no IP") + " · " + memoryText + " · " + failed + " failed units"
}

function networkText(raw) {
  var value = parseObject(raw)
  if (!value.mode) return "Network unavailable"
  return String(value.mode).toUpperCase() + " · " + String(value.link || "unknown") + (value.ip ? " · " + value.ip : "")
}

function defaultResources() {
  return {
    available: false,
    profile: "custom",
    running: false,
    cpus: { maximum: 1, configured: 1, live: 1 },
    memory: { maximumBytes: 1073741824, configuredBytes: 1073741824 },
    host: { cpus: 1, memoryBytes: 1073741824, balancedCpus: 1, balancedMemoryBytes: 1073741824, performanceCpus: 1, performanceMemoryBytes: 1073741824, fullCpus: 1, fullMemoryBytes: 1073741824, safeCpus: 1, safeMemoryBytes: 1073741824 }
  }
}

function parseResources(raw) {
  var fallback = defaultResources()
  var value = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : parseObject(raw)
  if (value.available === false || !value.cpus || !value.memory) return fallback

  var maximumCpus = Math.max(1, Math.floor(Number(value.cpus.maximum) || 1))
  var configuredCpus = Math.max(1, Math.min(maximumCpus, Math.floor(Number(value.cpus.configured) || 1)))
  var liveCpus = Math.max(1, Math.min(maximumCpus, Math.floor(Number(value.cpus.live) || configuredCpus)))
  var maximumMemoryBytes = Math.max(1073741824, Math.floor(Number(value.memory.maximumBytes) || 1073741824))
  var configuredMemoryBytes = Math.max(1073741824, Math.min(maximumMemoryBytes, Math.floor(Number(value.memory.configuredBytes) || 1073741824)))
  var profile = ["light", "balanced", "performance", "full", "custom"].indexOf(String(value.profile || "")) !== -1 ? String(value.profile) : "custom"
  var host = value.host || {}
  var hostCpus = Math.max(maximumCpus, Math.floor(Number(host.cpus) || maximumCpus))
  var hostMemoryBytes = Math.max(maximumMemoryBytes, Math.floor(Number(host.memoryBytes) || maximumMemoryBytes))
  var safeCpus = Math.max(1, Math.min(hostCpus, Math.floor(Number(host.safeCpus) || maximumCpus)))
  var safeMemoryBytes = Math.max(1073741824, Math.min(hostMemoryBytes, Math.floor(Number(host.safeMemoryBytes) || maximumMemoryBytes)))
  var balancedCpus = Math.max(1, Math.min(safeCpus, Math.floor(Number(host.balancedCpus) || Number(host.recommendedCpus) || Math.min(4, safeCpus))))
  var balancedMemoryBytes = Math.max(1073741824, Math.min(safeMemoryBytes, Math.floor(Number(host.balancedMemoryBytes) || Number(host.recommendedMemoryBytes) || Math.min(8589934592, safeMemoryBytes))))
  var performanceCpus = Math.max(1, Math.min(safeCpus, Math.floor(Number(host.performanceCpus) || Math.min(8, safeCpus))))
  var performanceMemoryBytes = Math.max(1073741824, Math.min(safeMemoryBytes, Math.floor(Number(host.performanceMemoryBytes) || Math.min(17179869184, safeMemoryBytes))))
  var fullCpus = Math.max(1, Math.min(safeCpus, Math.floor(Number(host.fullCpus) || Math.min(16, safeCpus))))
  var fullMemoryBytes = Math.max(1073741824, Math.min(safeMemoryBytes, Math.floor(Number(host.fullMemoryBytes) || Math.min(34359738368, safeMemoryBytes))))

  return {
    available: true,
    profile: profile,
    running: value.running === true,
    cpus: { maximum: maximumCpus, configured: configuredCpus, live: liveCpus },
    memory: { maximumBytes: maximumMemoryBytes, configuredBytes: configuredMemoryBytes },
    host: { cpus: hostCpus, memoryBytes: hostMemoryBytes, balancedCpus: balancedCpus, balancedMemoryBytes: balancedMemoryBytes, performanceCpus: performanceCpus, performanceMemoryBytes: performanceMemoryBytes, fullCpus: fullCpus, fullMemoryBytes: fullMemoryBytes, safeCpus: safeCpus, safeMemoryBytes: safeMemoryBytes }
  }
}

function memoryGiB(bytes) {
  return Math.max(1, Math.floor(Number(bytes || 0) / 1073741824))
}

function profileAllocation(resources, profile) {
  var value = parseResources(resources)
  var safeCpus = value.host.safeCpus
  var safeMemoryGiB = memoryGiB(value.host.safeMemoryBytes)
  var cpus = safeCpus
  var memory = safeMemoryGiB
  if (profile === "light") {
    cpus = 2
    memory = 4
  } else if (profile === "balanced") {
    cpus = value.host.balancedCpus
    memory = memoryGiB(value.host.balancedMemoryBytes)
  } else if (profile === "performance") {
    cpus = value.host.performanceCpus
    memory = memoryGiB(value.host.performanceMemoryBytes)
  } else if (profile === "full") {
    cpus = value.host.fullCpus
    memory = memoryGiB(value.host.fullMemoryBytes)
  }
  return {
    cpus: Math.min(cpus, safeCpus),
    memoryGiB: Math.min(memory, safeMemoryGiB)
  }
}

function resourceLimitsText(raw) {
  var value = parseResources(raw)
  if (!value.available) return "Host limits unavailable"
  return "Host: " + value.host.cpus + " cores / " + memoryGiB(value.host.memoryBytes) + " GiB" +
    " · custom limit: " + value.host.safeCpus + " cores / " + memoryGiB(value.host.safeMemoryBytes) + " GiB" +
    " · VM ceiling: " + value.cpus.maximum + " cores / " + memoryGiB(value.memory.maximumBytes) + " GiB"
}

function resourceText(raw) {
  var value = parseResources(raw)
  if (!value.available) return "Resources unavailable"
  var label = value.profile.charAt(0).toUpperCase() + value.profile.slice(1)
  return label + " · " + value.cpus.configured + " vCPU · " + memoryGiB(value.memory.configuredBytes) + " GiB"
}

function deploymentText(raw) {
  var value = parseObject(raw)
  var host = value.host || {}
  if (!host.commit) return "No checkout deployed"
  return String(host.branch || "detached") + " @ " + String(host.commit).slice(0, 10) + (host.dirty ? " · dirty" : "") + (value.synchronized ? " · synchronized" : " · guest differs")
}

function goldText(raw) {
  var value = parseObject(raw)
  if (!value.base) return "Gold image unavailable"
  var version = value.currentGuestVersion || "unknown version"
  return String(version) + " · " + Number(value.checkpointCount || 0) + " checkpoints · ISO " + String(value.newestCachedIso || "none")
}

function worktreeOptions(raw) {
  return parseArray(raw, "worktrees").map(function(item) {
    var branch = item.branch || "detached"
    var state = item.dirty ? "dirty" : "clean"
    return { value: String(item.path || ""), label: branch + " · " + state + " · " + String(item.path || "") }
  }).filter(function(item) { return item.value !== "" })
}

function branchOptions(raw) {
  return parseArray(raw, "branches").map(function(item) {
    var branch = String(item.branch || "")
    var commit = String(item.commit || "").slice(0, 10)
    var state = item.checkedOut ? (item.dirty ? "checked out · dirty" : "checked out") : "local branch"
    return { value: branch, label: branch, description: commit + " · " + state }
  }).filter(function(item) { return item.value !== "" })
}

function checkpointOptions(raw) {
  return parseArray(raw, "checkpoints").map(function(item) {
    return { value: String(item.name || ""), label: String(item.name || "") + " · " + String(item.createdAt || "") }
  }).filter(function(item) { return item.value !== "" })
}

function scenarioOptions(raw) {
  return parseArray(raw, "scenarios").map(function(item) {
    return { value: String(item.name || ""), label: String(item.name || "") + " · " + String(item.description || "") }
  }).filter(function(item) { return item.value !== "" })
}

function artifactText(raw) {
  var items = parseArray(raw, "artifacts")
  if (items.length === 0) return "No captured artifacts"
  return items.length + " artifacts · latest " + String(items[0].type || "file") + " · " + String(items[0].path || "")
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultStatus: defaultStatus,
    parseStatus: parseStatus,
    parseBarStatus: parseBarStatus,
    statusText: statusText,
    validAspect: validAspect,
    parseObject: parseObject,
    parseArray: parseArray,
    healthText: healthText,
    networkText: networkText,
    defaultResources: defaultResources,
    parseResources: parseResources,
    memoryGiB: memoryGiB,
    profileAllocation: profileAllocation,
    resourceLimitsText: resourceLimitsText,
    resourceText: resourceText,
    deploymentText: deploymentText,
    goldText: goldText,
    worktreeOptions: worktreeOptions,
    branchOptions: branchOptions,
    checkpointOptions: checkpointOptions,
    scenarioOptions: scenarioOptions,
    artifactText: artifactText
  }
}
