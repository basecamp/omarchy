// Pure display logic for the backup panel. omarchy-backup-run owns the truth in
// status.json; nothing here ever asks restic anything, which is what keeps the
// panel instant and the repository untouched by an open panel.

function defaultStatus() {
  return {
    phase: "unconfigured",
    progress: {percent: 0, bytes_done: 0, bytes_total: 0, files_done: 0},
    last_backup: {time: 0, snapshot: "", result: "", error: "", unreadable: []},
    last_complete: {time: 0, snapshot: ""},
    last_maintenance: {time: 0, result: "", error: ""},
    last_skip: {time: 0, reason: ""},
    snapshots: [],
    destination: {label: "", kind: "", offsite: true},
    repository: {size_bytes: 0, snapshot_count: 0},
    pause: {until: 0, reason: ""}
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()

  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    return merge(defaultStatus(), parsed)
  } catch (e) {
    return defaultStatus()
  }
}

function merge(base, overlay) {
  for (var key in overlay) {
    var value = overlay[key]
    if (value && typeof value === "object" && !Array.isArray(value) && base[key]) {
      base[key] = merge(base[key], value)
    } else if (value !== null && value !== undefined) {
      base[key] = value
    }
  }
  return base
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"

  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }

  var decimals = value >= 100 || index === 0 ? 0 : 1
  return value.toFixed(decimals).replace(/\.0$/, "") + " " + units[index]
}

function relativeTime(timestampSec, nowMs) {
  var timestamp = Number(timestampSec || 0)
  if (!isFinite(timestamp) || timestamp <= 0) return "never"

  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - timestamp * 1000) / 1000))

  if (diff < 60) return "just now"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + " minute" + (minutes === 1 ? "" : "s") + " ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + " hour" + (hours === 1 ? "" : "s") + " ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + " day" + (days === 1 ? "" : "s") + " ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + " month" + (months === 1 ? "" : "s") + " ago"
  return Math.floor(days / 365) + "y ago"
}

function stale(status, staleAfterHours, nowMs) {
  var last = Number(status.last_complete.time || 0)
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var limit = Number(staleAfterHours || 24) * 3600 * 1000

  if (status.phase === "unconfigured") return false
  if (last <= 0) return status.last_backup.time > 0
  return (now - last * 1000) > limit
}

// The bar earns attention only for things a person has to act on: a failed run,
// a snapshot that is missing files, or a backup that has quietly stopped
// happening. A paused backup is a choice, not a problem.
function attention(status, staleAfterHours, nowMs) {
  if (status.phase === "paused" || status.phase === "unconfigured") return false
  if (status.last_backup.result === "failed") return true
  if (status.last_backup.result === "partial") return true
  return stale(status, staleAfterHours, nowMs)
}

function heroMeta(status, staleAfterHours, nowMs) {
  switch (status.phase) {
  case "unconfigured":
    return "Not set up"
  case "running":
    return "Backing up " + Number(status.progress.percent || 0) + "%"
  case "paused":
    return pauseText(status, nowMs)
  }

  if (status.last_backup.result === "failed") return "Last run failed"
  if (Number(status.last_backup.time || 0) <= 0) return "No backup yet"

  // The destination has its own line below. Naming it here too only made the
  // hero long enough to elide.
  return "Backed up " + relativeTime(status.last_backup.time, nowMs)
}

function pauseText(status, nowMs) {
  var until = Number(status.pause.until || 0)
  if (until <= 0) return "Paused until resumed"

  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var minutes = Math.round((until * 1000 - now) / 60000)
  if (minutes <= 0) return "Resuming"
  if (minutes < 60) return "Paused for " + minutes + " more minutes"
  return "Paused for " + Math.round(minutes / 60) + " more hours"
}

function repositoryText(status) {
  var count = Number(status.repository.snapshot_count || 0)
  if (count <= 0) return "No snapshots yet"
  return formatBytes(status.repository.size_bytes) + " in " + count + " backup" + (count === 1 ? "" : "s")
}

function progressText(status) {
  var done = formatBytes(status.progress.bytes_done)
  var total = Number(status.progress.bytes_total || 0)
  if (total <= 0) return done
  return done + " of " + formatBytes(total)
}

function snapshotLabel(snapshot, nowMs) {
  if (!snapshot) return ""
  var when = relativeTime(snapshot.time, nowMs)
  return when.charAt(0).toUpperCase() + when.slice(1)
}

function problem(status) {
  if (status.phase === "unconfigured") return ""
  if (status.last_backup.result === "failed") return String(status.last_backup.error || "The last backup failed")
  if (status.last_backup.result === "partial") {
    var paths = status.last_backup.unreadable || []
    return paths.length > 0
      ? "Could not read " + paths.length + " path" + (paths.length === 1 ? "" : "s") + ", starting with " + paths[0]
      : "Some files could not be read"
  }
  if (Number(status.last_skip.time || 0) > Number(status.last_backup.time || 0) && status.last_skip.reason) {
    return "Last run skipped: " + status.last_skip.reason
  }
  return ""
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultStatus: defaultStatus,
    parseStatus: parseStatus,
    formatBytes: formatBytes,
    relativeTime: relativeTime,
    stale: stale,
    attention: attention,
    heroMeta: heroMeta,
    pauseText: pauseText,
    repositoryText: repositoryText,
    progressText: progressText,
    snapshotLabel: snapshotLabel,
    problem: problem
  }
}
