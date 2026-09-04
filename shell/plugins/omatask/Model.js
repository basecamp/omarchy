.pragma library

// Formatting and small data transforms for the task manager. Kept out of the
// QML so the panel and the overlay format identically and neither has to
// re-derive the rules.

// Dimming has to know what it is dimming *against*. "Less prominent" means
// darker on a dark ground and lighter on a light one; picking the wrong
// direction makes secondary text louder than the text it sits behind. Six
// components needed this, and six copies were six chances to diverge.
function groundIsDark(ground) {
  return (ground.r * 0.2126 + ground.g * 0.7152 + ground.b * 0.0722) < 0.5
}

function dim(ground, color, amount) {
  return groundIsDark(ground) ? Qt.darker(color, amount) : Qt.lighter(color, amount)
}

var KIB = 1024

function formatBytes(bytes, digits) {
  var value = Number(bytes) || 0
  if (value < KIB) return Math.round(value) + " B"
  var units = ["KB", "MB", "GB", "TB", "PB"]
  var index = -1
  do {
    value /= KIB
    index++
  } while (value >= KIB && index < units.length - 1)
  var places = digits === undefined ? (value < 10 ? 1 : 0) : digits
  return value.toFixed(places) + " " + units[index]
}

function formatRate(bytesPerSecond) {
  return formatBytes(bytesPerSecond) + "/s"
}

// Uptime as the coarsest two units that still carry information — "3d 4h"
// rather than "3d 4h 12m 7s", which nobody reads past the first field.
function formatUptime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var days = Math.floor(total / 86400)
  var hours = Math.floor((total % 86400) / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + minutes + "m"
  return minutes + "m " + (total % 60) + "s"
}

function formatPercent(value, digits) {
  var n = Number(value) || 0
  return n.toFixed(digits === undefined ? 1 : digits) + "%"
}

// Process state letters from /proc/<pid>/stat, spelled out for the detail row.
var STATE_NAMES = {
  "R": "Running",
  "S": "Sleeping",
  "D": "Waiting on I/O",
  "Z": "Zombie",
  "T": "Stopped",
  "t": "Traced",
  "X": "Dead",
  "I": "Idle"
}

function stateName(letter) {
  return STATE_NAMES[String(letter)] || String(letter || "")
}

// Push onto a fixed-length ring, returning a new array. QML property bindings
// only re-evaluate on assignment, so mutating in place would leave the graphs
// showing stale data.
function pushHistory(history, value, limit) {
  var next = (history || []).slice()
  next.push(Number(value) || 0)
  var max = Math.max(2, Number(limit) || 60)
  if (next.length > max) next = next.slice(next.length - max)
  return next
}

// Largest value in a series, for pinning two graphs to one scale. Overlaying
// series that each autoscale independently draws a picture that is worse than
// no picture — the lines imply a relationship their axes do not share.
function peak(values) {
  var highest = 0
  var list = values || []
  for (var i = 0; i < list.length; i++) {
    var value = Number(list[i]) || 0
    if (value > highest) highest = value
  }
  return highest
}

// Same as pushHistory, once per core. Returns a fresh outer array so a QML
// binding on it actually re-evaluates; core count can change under us on a
// machine that hotplugs CPUs, so the ring set is resized rather than assumed.
function pushCoreHistories(histories, cores, limit) {
  var values = cores || []
  var next = []
  for (var i = 0; i < values.length; i++) {
    next.push(pushHistory((histories || [])[i], values[i], limit))
  }
  return next
}

// The commands a process list can be sorted by. `key` reads the field off a
// row; every one sorts descending first, because "what is using the most" is
// the question being asked.
var SORTS = [
  { id: "cpu", label: "CPU", key: function(p) { return p.cpu } },
  { id: "rss", label: "Memory", key: function(p) { return p.rss } },
  { id: "threads", label: "Threads", key: function(p) { return p.threads } },
  { id: "pid", label: "PID", key: function(p) { return p.pid } },
  { id: "name", label: "Name", key: function(p) { return String(p.name).toLowerCase() } }
]

function sortById(id) {
  for (var i = 0; i < SORTS.length; i++) {
    if (SORTS[i].id === id) return SORTS[i]
  }
  return SORTS[0]
}

function sortProcesses(processes, sortId, descending) {
  var sort = sortById(sortId)
  var rows = (processes || []).slice()
  var direction = descending ? -1 : 1
  rows.sort(function(a, b) {
    var left = sort.key(a)
    var right = sort.key(b)
    if (left < right) return -direction
    if (left > right) return direction
    return a.pid - b.pid  // stable tiebreak so equal rows stop swapping places
  })
  return rows
}

// Case-insensitive match against the process name, its full command line, the
// owning user, and the pid — so "1234", "chrome", and "root" all work.
function filterProcesses(processes, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return processes || []
  return (processes || []).filter(function(p) {
    return String(p.name).toLowerCase().indexOf(needle) !== -1
      || String(p.cmd).toLowerCase().indexOf(needle) !== -1
      || String(p.user).toLowerCase().indexOf(needle) !== -1
      || String(p.pid).indexOf(needle) !== -1
  })
}

// Strip the interpreter and path noise so a row reads as the thing the user
// launched: "/usr/lib/chromium/chromium --type=renderer …" becomes
// "chromium --type=renderer …".
function shortCommand(cmd, name) {
  var text = String(cmd || "").trim()
  if (text === "") return String(name || "")
  var space = text.indexOf(" ")
  var head = space === -1 ? text : text.substring(0, space)
  var tail = space === -1 ? "" : text.substring(space)
  var slash = head.lastIndexOf("/")
  if (slash !== -1) head = head.substring(slash + 1)
  return head + tail
}

// ---------------------------------------------------------------- applications

var APP_SORTS = [
  { id: "cpu", key: function(a) { return a.cpu } },
  { id: "mem", key: function(a) { return a.mem } },
  { id: "rss", key: function(a) { return a.mem } },
  { id: "ioStall", key: function(a) { return a.ioStall } },
  { id: "procs", key: function(a) { return a.procs } },
  { id: "pid", key: function(a) { return a.procs } },
  { id: "name", key: function(a) { return String(a.name).toLowerCase() } }
]

function sortApps(apps, sortId, descending) {
  var sort = APP_SORTS[0]
  for (var i = 0; i < APP_SORTS.length; i++) {
    if (APP_SORTS[i].id === sortId) sort = APP_SORTS[i]
  }
  var rows = (apps || []).slice()
  var direction = descending ? -1 : 1
  rows.sort(function(a, b) {
    var left = sort.key(a), right = sort.key(b)
    if (left < right) return -direction
    if (left > right) return direction
    // The tie-break has to be a total order, equality included: a comparator
    // that never returns 0 lets two identical rows swap places between renders.
    var leftUnit = String(a.unit), rightUnit = String(b.unit)
    if (leftUnit < rightUnit) return -1
    if (leftUnit > rightUnit) return 1
    return 0
  })
  return rows
}

function filterApps(apps, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return apps || []
  return (apps || []).filter(function(a) {
    return String(a.name).toLowerCase().indexOf(needle) !== -1
      || String(a.unit).toLowerCase().indexOf(needle) !== -1
  })
}

// ---------------------------------------------------------------- process tree
//
// Flatten parent/child structure back into a list, because a ListView wants a
// flat model. Each row carries its `depth`, and the order is a depth-first walk
// of the forest — so the list reads as a tree while staying cheap to render.
function buildTree(rows) {
  var byPid = {}
  var children = {}
  var i
  for (i = 0; i < rows.length; i++) {
    byPid[rows[i].pid] = rows[i]
  }
  for (i = 0; i < rows.length; i++) {
    var parent = rows[i].ppid
    // A process whose parent is outside the set (or is itself) is a root.
    var key = (byPid[parent] !== undefined && parent !== rows[i].pid) ? parent : "roots"
    if (!children[key]) children[key] = []
    children[key].push(rows[i])
  }

  var out = []
  var guard = 0
  function walk(list, depth) {
    if (!list || depth > 24) return
    for (var j = 0; j < list.length; j++) {
      if (++guard > 5000) return          // cycle guard; /proc can lie briefly
      var row = list[j]
      var copy = {}
      for (var k in row) copy[k] = row[k]
      copy.depth = depth
      copy.hasChildren = !!children[row.pid]
      out.push(copy)
      walk(children[row.pid], depth + 1)
    }
  }
  walk(children["roots"], 0)
  return out
}
