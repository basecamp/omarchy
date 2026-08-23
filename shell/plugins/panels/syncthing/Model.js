function defaultSnapshot() {
  return {
    ok: true,
    installed: false,
    running: false,
    authenticated: false,
    reason: "unavailable",
    serviceState: "inactive",
    overall: "unavailable",
    guiUrl: "",
    myID: "",
    myName: "Syncthing",
    syncPercent: 100,
    totalNeedBytes: 0,
    totalNeedItems: 0,
    folders: [],
    devices: [],
    pendingDevices: [],
    pendingFolders: [],
    systemErrors: []
  }
}

function parseSnapshot(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultSnapshot()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultSnapshot()
    var result = defaultSnapshot()
    for (var key in parsed) result[key] = parsed[key]
    result.folders = Array.isArray(parsed.folders) ? parsed.folders : []
    result.devices = Array.isArray(parsed.devices) ? parsed.devices : []
    result.pendingDevices = Array.isArray(parsed.pendingDevices) ? parsed.pendingDevices : []
    result.pendingFolders = Array.isArray(parsed.pendingFolders) ? parsed.pendingFolders : []
    result.systemErrors = Array.isArray(parsed.systemErrors) ? parsed.systemErrors : []
    return result
  } catch (error) {
    var failed = defaultSnapshot()
    failed.ok = false
    failed.reason = "parse-error"
    failed.overall = "error"
    failed.lastError = "Failed to parse Syncthing status"
    return failed
  }
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value /= 1000
    index++
  }
  var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index]
}

function formatPercent(value) {
  var number = Number(value)
  if (!isFinite(number)) return "—"
  number = Math.max(0, Math.min(100, number))
  if (number >= 10) return Math.round(number) + "%"
  return number.toFixed(1).replace(/\.0$/, "") + "%"
}

function relativeTime(value, nowMs) {
  var timestamp = new Date(String(value || "")).getTime()
  if (!isFinite(timestamp) || timestamp <= 0) return "Never"
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var seconds = Math.max(0, Math.floor((now - timestamp) / 1000))
  if (seconds < 60) return "Just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

function prettyPath(path, home) {
  var value = String(path || "")
  var prefix = String(home || "")
  if (prefix !== "" && (value === prefix || value.indexOf(prefix + "/") === 0))
    return "~" + value.substring(prefix.length)
  return value
}

function folderHasProblem(folder) {
  if (!folder) return false
  return Number(folder.errorCount || 0) > 0
    || String(folder.error || "") !== ""
    || String(folder.watchError || "") !== ""
    || String(folder.state || "") === "error"
}

function folderIsBusy(folder) {
  var state = String((folder && folder.state) || "")
  return state === "scanning" || state === "scan-waiting"
    || state === "syncing" || state === "sync-preparing"
    || state === "cleaning"
}

function folderStatusText(folder) {
  if (!folder) return "Unknown"
  if (folder.paused === true) return "Paused"
  if (folderHasProblem(folder)) {
    var count = Number(folder.errorCount || 0)
    if (count > 0) return count + (count === 1 ? " error" : " errors")
    return String(folder.error || folder.watchError || "Needs attention")
  }
  var state = String(folder.state || "unknown")
  if (state === "scanning" || state === "scan-waiting") return "Scanning"
  if (state === "syncing" || state === "sync-preparing") return "Syncing · " + formatPercent(folder.completion)
  if (Number(folder.needBytes || 0) > 0) return formatBytes(folder.needBytes) + " behind"
  if (state === "idle") return "Up to date"
  return state.charAt(0).toUpperCase() + state.substring(1).replace(/-/g, " ")
}

function statusText(snapshot) {
  var data = snapshot || defaultSnapshot()
  if (!data.installed) return "Not installed"
  if (!data.running) return data.serviceState === "failed" ? "Service failed" : "Stopped"
  if (!data.authenticated) return data.reason === "nonlocal-api" ? "Non-local API unsupported" : "API unavailable"
  if (data.overall === "error") return "Needs attention"
  if (data.overall === "attention") return "New sharing request"
  if (data.overall === "syncing") return "Syncing · " + formatPercent(data.syncPercent)
  if (data.overall === "scanning") return "Scanning folders"
  if (data.overall === "paused") return "All folders paused"
  return "Up to date"
}

function folderProblemKeys(snapshot) {
  var rows = []
  var folders = snapshot && Array.isArray(snapshot.folders) ? snapshot.folders : []
  for (var i = 0; i < folders.length; i++) {
    var folder = folders[i] || {}
    var errors = Array.isArray(folder.errors) ? folder.errors : []
    if (errors.length === 0 && folderHasProblem(folder)) {
      rows.push(String(folder.id || "folder") + "\n" + String(folder.error || folder.watchError || folder.state || "error"))
    }
    for (var j = 0; j < errors.length; j++) {
      var entry = errors[j] || {}
      rows.push(String(folder.id || "folder") + "\n" + String(entry.path || "") + "\n" + String(entry.error || "error"))
    }
  }
  rows.sort()
  return rows
}

function problemKeys(snapshot) {
  var rows = folderProblemKeys(snapshot)
  var errors = snapshot && Array.isArray(snapshot.systemErrors) ? snapshot.systemErrors : []
  for (var i = 0; i < errors.length; i++) {
    var entry = errors[i] || {}
    rows.push("system\n" + String(entry.when || "") + "\n" + String(entry.message || "error"))
  }
  rows.sort()
  return rows
}

function pendingKeys(snapshot) {
  var rows = []
  var devices = snapshot && Array.isArray(snapshot.pendingDevices) ? snapshot.pendingDevices : []
  var folders = snapshot && Array.isArray(snapshot.pendingFolders) ? snapshot.pendingFolders : []
  for (var i = 0; i < devices.length; i++) rows.push("device:" + String(devices[i].id || ""))
  for (var j = 0; j < folders.length; j++) rows.push("folder:" + String(folders[j].id || "") + ":" + String(folders[j].deviceId || ""))
  rows.sort()
  return rows
}

function addedKeys(previous, current) {
  var old = {}
  var before = Array.isArray(previous) ? previous : []
  var after = Array.isArray(current) ? current : []
  for (var i = 0; i < before.length; i++) old[String(before[i])] = true
  var added = []
  for (var j = 0; j < after.length; j++) if (!old[String(after[j])]) added.push(String(after[j]))
  return added
}

function deviceById(devices, id) {
  var rows = Array.isArray(devices) ? devices : []
  for (var i = 0; i < rows.length; i++) if (String(rows[i].id || "") === String(id || "")) return rows[i]
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultSnapshot: defaultSnapshot,
    parseSnapshot: parseSnapshot,
    formatBytes: formatBytes,
    formatPercent: formatPercent,
    relativeTime: relativeTime,
    prettyPath: prettyPath,
    folderHasProblem: folderHasProblem,
    folderIsBusy: folderIsBusy,
    folderStatusText: folderStatusText,
    statusText: statusText,
    folderProblemKeys: folderProblemKeys,
    problemKeys: problemKeys,
    pendingKeys: pendingKeys,
    addedKeys: addedKeys,
    deviceById: deviceById
  }
}
