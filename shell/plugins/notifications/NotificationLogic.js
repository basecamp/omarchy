function isChromiumDerived(app, appIcon) {
  var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
  return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 ||
         source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 ||
         source.indexOf("opera") >= 0
}

function sanitizeBody(body, app, appIcon) {
  var text = String(body || "").replace(/<img[^>]*>/gi, "")
  if (!isChromiumDerived(app, appIcon)) return text

  return text
    .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
    .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
}

function summaryStartsWithGlyph(summary) {
  var text = String(summary || "").replace(/^\s+/, "")
  if (!text) return false

  var offset = 1
  var first = text.charCodeAt(0)
  if (first >= 0xd800 && first <= 0xdbff && text.length > 1) offset = 2

  var spaces = 0
  while (offset < text.length && text.charAt(offset) === " ") {
    spaces++
    offset++
  }

  return spaces >= 2
}

function shouldBypassDnd(notification, criticalUrgency) {
  var appName = String((notification && notification.appName) || "")
  if (appName === "omarchy-action") return true
  return appName === "notify-send" && notification && notification.urgency === criticalUrgency
}

function isEphemeralApp(appName) {
  var name = String(appName || "")
  return name === "notify-send" || name === "omarchy-action"
}

function stringHint(hints, name) {
  try {
    if (hints) {
      var value = hints[name]
      if (value !== undefined && value !== null) return String(value)
    }
  } catch (e) {
  }
  return ""
}

function glyphFromHints(hints) {
  return stringHint(hints, "omarchy-glyph")
}

// Shell command to run when the card is clicked, sent by
// omarchy-notification-send --exec. Carrying the action as data means it
// travels with the popup through the persistence files, so a toast restored
// after a shell restart clicks through exactly like a live one. A libnotify
// action can't: its sender is still waiting on an id from a server generation
// that no longer exists.
function execFromHints(hints) {
  return stringHint(hints, "omarchy-exec")
}

function shouldRenderCompactGlyph(glyph, iconSource, singleLineToast) {
  return String(glyph || "").length > 0 && String(iconSource || "").length === 0 && !!singleLineToast
}

function snapshotOf(notification, timestamp) {
  var n = notification || {}
  var id = n.id || 0
  var expireTimeout = Number(n.expireTimeout || 0)
  if (!isFinite(expireTimeout) || expireTimeout < 0) expireTimeout = 0
  return {
    id: id,
    originalId: id,
    app: n.appName || "",
    appIcon: n.appIcon || "",
    summary: String(n.summary || ""),
    body: n.body || "",
    image: n.image || "",
    glyph: glyphFromHints(n.hints),
    exec: execFromHints(n.hints),
    urgency: n.urgency,
    expireTimeout: expireTimeout,
    timestamp: timestamp === undefined ? Date.now() : timestamp
  }
}

function historyEntry(value, normalUrgency) {
  var e = value || {}
  return {
    id: e.id || 0,
    originalId: e.originalId || e.id || 0,
    app: e.app || "",
    appIcon: e.appIcon || "",
    summary: e.summary || "",
    body: e.body || "",
    image: e.image || "",
    glyph: e.glyph || "",
    exec: e.exec || "",
    urgency: typeof e.urgency === "number" ? e.urgency : normalUrgency,
    expireTimeout: 0,
    timestamp: e.timestamp || 0
  }
}

function dedupeByOriginalId(rows) {
  var values = Array.isArray(rows) ? rows : []
  var keep = {}
  for (var i = 0; i < values.length; i++) {
    var row = values[i]
    if (!row) continue
    var key = row.originalId
    if (key === undefined || key === null) key = "_" + i
    var prior = keep[key]
    if (!prior || (row.timestamp || 0) >= (prior.timestamp || 0)) keep[key] = row
  }

  var out = []
  for (var id in keep) out.push(keep[id])
  out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out
}

function parseHistory(raw, normalUrgency, historyCap) {
  var text = String(raw || "").trim()
  var cap = historyCap === undefined || historyCap === null ? 100 : Number(historyCap)
  if (isNaN(cap)) cap = 100
  cap = Math.max(0, cap)
  if (!text) return { empty: true, error: false, dnd: null, pending: [], past: [], hadDuplicates: false }

  try {
    var parsed = JSON.parse(text)
    var pendingRaw = (parsed && Array.isArray(parsed.pending)) ? parsed.pending : []
    var pastRaw = (parsed && Array.isArray(parsed.past)) ? parsed.past : []
    if (parsed && Array.isArray(parsed.entries)) pastRaw = pastRaw.concat(parsed.entries)

    var pendingDeduped = dedupeByOriginalId(pendingRaw)
    var pastDeduped = dedupeByOriginalId(pastRaw)

    return {
      empty: false,
      error: false,
      dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null,
      pending: pendingDeduped.slice(0, cap).map(function(entry) { return historyEntry(entry, normalUrgency) }),
      past: pastDeduped.slice(0, cap).map(function(entry) { return historyEntry(entry, normalUrgency) }),
      hadDuplicates: pendingDeduped.length !== pendingRaw.length || pastDeduped.length !== pastRaw.length
    }
  } catch (e) {
    return { empty: false, error: true, errorMessage: String(e), dnd: null, pending: [], past: [], hadDuplicates: false }
  }
}

function recentHistoryRows(pending, past, limit, normalUrgency) {
  var max = limit === undefined || limit === null ? 5 : Number(limit)
  if (isNaN(max)) max = 5
  max = Math.max(0, max)

  var values = []
  function collect(rows) {
    var source = Array.isArray(rows) ? rows : []
    for (var i = 0; i < source.length; i++) {
      if (source[i]) values.push(source[i])
    }
  }
  collect(pending)
  collect(past)

  var keep = {}
  for (var j = 0; j < values.length; j++) {
    var row = values[j]
    var key = row.originalId
    if (key === undefined || key === null) key = row.id
    if (key === undefined || key === null) key = "_" + j
    var prior = keep[key]
    if (!prior || (row.timestamp || 0) >= (prior.timestamp || 0)) keep[key] = row
  }

  var out = []
  for (var id in keep) out.push(historyEntry(keep[id], normalUrgency))
  out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out.slice(0, max)
}

function dumpRows(rows) {
  var values = Array.isArray(rows) ? rows : []
  var out = []
  for (var i = 0; i < values.length; i++) {
    var r = values[i]
    if (!r) continue
    out.push({
      id: r.id,
      originalId: r.originalId,
      app: r.app,
      appIcon: r.appIcon,
      summary: r.summary,
      body: r.body,
      image: r.image,
      glyph: r.glyph || "",
      exec: r.exec || "",
      urgency: r.urgency,
      timestamp: r.timestamp
    })
  }
  return out
}

// ---------------------------------------------------- popup persistence
//
// Each on-screen popup is mirrored to its own file under
// ~/.local/state/omarchy/notifications/ so toasts survive shell restarts
// (e.g. the restart `omarchy-update` performs). The file exists exactly as
// long as the popup is on screen: it is written when the toast appears and
// deleted when the toast expires, is dismissed, or its action is invoked.

function popupEntry(value, normalUrgency) {
  var entry = historyEntry(value, normalUrgency)
  var expire = Number((value || {}).expireTimeout || 0)
  if (!isFinite(expire) || expire < 0) expire = 0
  entry.expireTimeout = expire
  // Absolute expiry deadline, set only when a restore resets a surviving
  // popup's display lifetime. Kept out of the entry entirely when unset so
  // restored rows match the roles of freshly received ones.
  var deadline = Number((value || {}).deadline || 0)
  if (isFinite(deadline) && deadline > 0) entry.deadline = deadline
  return entry
}

function popupFileName(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || 0) + ".json"
}

function serializePopup(entry, normalUrgency) {
  // Compact (single-line) on purpose: restore cats every file together and
  // parses line by line, which only works when each file is one line.
  return JSON.stringify(popupEntry(entry, normalUrgency))
}

// Parse the concatenation of every persisted popup file into entries,
// newest-first. Deliberately NO dedupe by originalId: ids restart from 1
// with every server process, so two files sharing an id are usually
// different generations — dropping the older one would silently discard a
// restored critical alert the moment a fresh notification reuses its id.
// The one case that leaves a genuine duplicate (a crash between a
// replacement's write and the replaced file's delete) merely re-shows a
// superseded toast, which expires or is dismissed and cleans itself up.
function parsePopupFiles(raw, normalUrgency) {
  var lines = String(raw || "").split("\n")
  var entries = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      if (value && typeof value === "object") entries.push(popupEntry(value, normalUrgency))
    } catch (e) {
      // A torn write from a crash mid-save — skip the line, keep the rest.
    }
  }
  entries.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return entries
}

// A persisted popup whose lifetime already ran out would have expired on
// screen had the shell kept running, so it is not restored. duration 0 means
// the popup never expires (critical urgency) and always survives restarts.
// A restore-reset deadline outranks the original timestamp: without it, a
// second restart would judge a re-shown toast by a clock that no longer
// governs its display and drop it while it is still on screen.
function popupExpired(entry, duration, now) {
  var deadline = Number((entry || {}).deadline || 0)
  if (isFinite(deadline) && deadline > 0) return Number(now) >= deadline
  var lifetime = Number(duration || 0)
  if (!isFinite(lifetime) || lifetime <= 0) return false
  return (Number(now) - Number((entry || {}).timestamp || 0)) >= lifetime
}

function popupPlacement(barPosition, barClearance, gapsOut) {
  var position = String(barPosition || "top")
  var clearance = Number(barClearance)
  var gap = Number(gapsOut)
  if (!isFinite(clearance)) clearance = 0
  if (!isFinite(gap)) gap = 0

  return {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: {
      top: position === "top" ? clearance : gap,
      bottom: gap,
      left: gap,
      right: position === "right" ? clearance : gap
    }
  }
}

function imageExtension(srcPath) {
  var lower = String(srcPath || "").toLowerCase()
  var dot = lower.lastIndexOf(".")
  if (dot < 0) return "png"
  var ext = lower.substring(dot + 1)
  if (ext.length === 0 || ext.length > 5) return "png"
  return ext
}

if (typeof module !== "undefined") {
  module.exports = {
    isChromiumDerived: isChromiumDerived,
    sanitizeBody: sanitizeBody,
    summaryStartsWithGlyph: summaryStartsWithGlyph,
    shouldBypassDnd: shouldBypassDnd,
    isEphemeralApp: isEphemeralApp,
    stringHint: stringHint,
    glyphFromHints: glyphFromHints,
    execFromHints: execFromHints,
    shouldRenderCompactGlyph: shouldRenderCompactGlyph,
    snapshotOf: snapshotOf,
    historyEntry: historyEntry,
    dedupeByOriginalId: dedupeByOriginalId,
    parseHistory: parseHistory,
    recentHistoryRows: recentHistoryRows,
    dumpRows: dumpRows,
    popupEntry: popupEntry,
    popupFileName: popupFileName,
    serializePopup: serializePopup,
    parsePopupFiles: parsePopupFiles,
    popupExpired: popupExpired,
    popupPlacement: popupPlacement,
    imageExtension: imageExtension
  }
}
