function isChromiumDerived(app, appIcon) {
  var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
  return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 ||
         source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 ||
         source.indexOf("opera") >= 0 || source.indexOf("helium") >= 0
}

function normalizedIdentity(value) {
  var text = String(value || "").trim().toLowerCase()
  if (text.slice(-8) === ".desktop") text = text.slice(0, -8)
  return text
}

function identityKey(prefix, value) {
  var normalized = normalizedIdentity(value)
  return normalized ? String(prefix || "") + ":" + encodeURIComponent(normalized) : ""
}

function applicationKey(desktopEntry) {
  return identityKey("desktop", desktopEntry)
}

function normalizedOrigin(value) {
  var match = String(value || "").trim().match(/^(https?):\/\/([^\/?#\s]+)/i)
  if (!match) return ""

  var scheme = match[1].toLowerCase()
  var authority = match[2].toLowerCase()
  authority = authority.slice(authority.lastIndexOf("@") + 1)
  if (scheme === "https" && authority.slice(-4) === ":443") authority = authority.slice(0, -4)
  if (scheme === "http" && authority.slice(-3) === ":80") authority = authority.slice(0, -3)
  return scheme + "://" + authority
}

function originKey(origin) {
  var value = normalizedOrigin(origin)
  return value ? "origin:" + encodeURIComponent(value) : ""
}

function webAppOrigin(command) {
  var parts = []
  if (command && typeof command !== "string" && typeof command.length === "number") {
    for (var p = 0; p < command.length; p++) parts.push(String(command[p] || ""))
  }
  for (var i = 0; i < parts.length; i++) {
    var part = String(parts[i] || "")
    if (part.indexOf("OMARCHY_WEBAPP_ORIGIN=") === 0)
      return normalizedOrigin(part.slice("OMARCHY_WEBAPP_ORIGIN=".length))
    if (/(^|\/)omarchy-launch-webapp$/.test(part) && i + 1 < parts.length)
      return normalizedOrigin(parts[i + 1])
  }

  var text = String(command || "")
  var metadata = text.match(/\bOMARCHY_WEBAPP_ORIGIN=(["']?)(https?:\/\/[^\s"']+)\1/i)
  if (metadata) return normalizedOrigin(metadata[2])
  var direct = text.match(/\bomarchy-launch-webapp\s+(["']?)(https?:\/\/[^\s"']+)\1/i)
  return direct ? normalizedOrigin(direct[2]) : ""
}

function browserOriginFromBody(body) {
  var text = String(body || "")
  var linked = text.match(/^\s*<a\b[^>]*href=["'](https?:\/\/[^\/"'#?]+)[^"']*["'][^>]*>/i)
  if (linked) return normalizedOrigin(linked[1])
  var plain = text.match(/^\s*(https?:\/\/[^\/\s]+)(?:\/\S*)?\s+/i)
  if (plain) return normalizedOrigin(plain[1])
  var www = text.match(/^\s*(www\.(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?)(?:\/\S*)?\s+/i)
  return www ? normalizedOrigin("https://" + www[1]) : ""
}

function notificationOriginHint(value) {
  var text = String(value || "").trim()
  if (!text) return ""
  return normalizedOrigin(/^https?:\/\//i.test(text) ? text : "https://" + text)
}

function notificationSource(notification) {
  var n = notification || {}
  var app = String(n.appName || "")
  var appIcon = String(n.appIcon || "")
  var desktopEntry = String(n.desktopEntry || stringHint(n.hints, "desktop-entry") || "")
    .replace(/\.desktop$/i, "")
  var browser = isChromiumDerived(app, appIcon + "\n" + desktopEntry)
  var source = browser ? browserOriginFromBody(n.body) || notificationOriginHint(stringHint(n.hints, "x-kde-origin-name")) : ""
  var baseKey = identityKey("desktop", desktopEntry) || identityKey("name", app)
  var key = baseKey
  if (key && source) key += "/" + identityKey("source", source)

  return {
    key: key,
    desktopEntry: desktopEntry,
    source: source
  }
}

function aliasKey(value) {
  var normalized = normalizedIdentity(value)
  return normalized ? "alias:" + normalized : ""
}

function claimAlias(aliases, value, key) {
  var alias = aliasKey(value)
  if (!alias) return
  if (aliases[alias] === undefined) aliases[alias] = key
  else if (aliases[alias] !== key) aliases[alias] = ""
}

function applicationAlias(aliases, value) {
  return aliases[aliasKey(value)] || ""
}

function buildApplicationCatalog(entries) {
  var input = Array.isArray(entries) ? entries : []
  var slots = []
  var groups = {}
  var keys = {}
  var aliases = {}
  var origins = {}

  for (var i = 0; i < input.length; i++) {
    var entry = input[i] || {}
    var desktopEntry = String(entry.id || "")
    var desktopKey = applicationKey(desktopEntry)
    if (!desktopKey) continue

    var label = String(entry.label || desktopEntry)
    var origin = webAppOrigin(entry.command || entry.execString)
    var source
    if (origin) {
      var groupKey = originKey(origin)
      source = groups[groupKey]
      if (!source) {
        source = { key: groupKey, origin: origin, members: [] }
        groups[groupKey] = source
        slots.push(source)
      }
      source.members.push({
        label: label,
        appIcon: String(entry.appIcon || ""),
        desktopEntry: desktopEntry,
        startupClass: String(entry.startupClass || "")
      })
      origins[origin] = groupKey
    } else {
      source = {
        key: desktopKey,
        origin: "",
        members: [{
          label: label,
          appIcon: String(entry.appIcon || ""),
          desktopEntry: desktopEntry,
          startupClass: String(entry.startupClass || "")
        }]
      }
      slots.push(source)
    }
  }

  var applications = []
  for (var s = 0; s < slots.length; s++) {
    var slot = slots[s]
    var first = slot.members[0]
    var labels = []
    var search = [slot.origin]
    for (var m = 0; m < slot.members.length; m++) {
      var member = slot.members[m]
      labels.push(member.label)
      search.push(member.label, member.desktopEntry, member.startupClass)
      claimAlias(aliases, member.desktopEntry, slot.key)
      claimAlias(aliases, member.label, slot.key)
      claimAlias(aliases, member.startupClass, slot.key)
    }
    var application = {
      key: slot.key,
      label: labels.join(" + "),
      app: first.label,
      appIcon: first.appIcon,
      desktopEntry: first.desktopEntry,
      source: slot.origin,
      searchText: search.join(" "),
      memberCount: slot.members.length
    }
    applications.push(application)
    keys[slot.key] = application
  }

  return { applications: applications, keys: keys, aliases: aliases, origins: origins }
}

function validApplicationMode(value) {
  var mode = String(value || "").toLowerCase()
  return mode === "normal" || mode === "history" || mode === "off" ? mode : "normal"
}

function normalizedApplicationModes(value) {
  var input = value && typeof value === "object" && !Array.isArray(value) ? value : {}
  var out = {}
  for (var key in input) {
    var normalizedKey = String(key || "")
    if (!normalizedKey) continue
    var mode = validApplicationMode(input[key])
    if (mode !== "normal") out[normalizedKey] = mode
  }
  return out
}

function deliveryTarget(mode, doNotDisturb, bypassDnd, ephemeral) {
  var applicationMode = validApplicationMode(mode)
  if (applicationMode === "off") return "drop"
  if (applicationMode === "history" || (!!doNotDisturb && !bypassDnd))
    return ephemeral ? "drop" : "history"
  return "popup"
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
  var source = notificationSource(n)
  var id = n.id || 0
  var expireTimeout = Number(n.expireTimeout || 0)
  if (!isFinite(expireTimeout) || expireTimeout < 0) expireTimeout = 0
  return {
    id: id,
    originalId: id,
    app: n.appName || "",
    appIcon: n.appIcon || "",
    sourceKey: source.key,
    source: source.source,
    desktopEntry: source.desktopEntry,
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

// Everything the popup card draws, and therefore everything an in-place
// update has to write through to the row and its file.
var POPUP_ROLES = ["app", "appIcon", "summary", "body", "image", "glyph", "exec", "urgency", "expireTimeout"]

function popupRoles() {
  return POPUP_ROLES
}

// Whether a refresh has anything to write. Each property a client updates
// emits its own signal, and the catch-up refresh after a row is inserted
// usually finds the object exactly as it was snapshotted — without this,
// one update would rewrite the file several times over.
function popupRowChanged(row, updated) {
  var current = row || {}
  var next = updated || {}
  for (var i = 0; i < POPUP_ROLES.length; i++) {
    var role = POPUP_ROLES[i]
    if (current[role] !== next[role]) return true
  }
  return false
}

// A client updating a notification through replaces_id keeps the identity of
// the popup it took over: the file name is the timestamp and id the popup was
// first persisted under, and the restore, replace and archive paths all key
// off that name. Only what the card draws comes from the updated object.
function replacementSnapshot(notification, originalId, timestamp, identity) {
  var updated = snapshotOf(notification, timestamp)
  updated.id = originalId
  updated.originalId = originalId
  if (identity) {
    updated.sourceKey = String(identity.sourceKey || "")
    updated.source = String(identity.source || "")
    updated.desktopEntry = String(identity.desktopEntry || "")
  }
  return updated
}

function historyEntry(value, normalUrgency) {
  var e = value || {}
  return {
    id: e.id || 0,
    originalId: e.originalId || e.id || 0,
    app: e.app || "",
    appIcon: e.appIcon || "",
    sourceKey: e.sourceKey || "",
    source: e.source || "",
    desktopEntry: e.desktopEntry || "",
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

// notifications.json keeps DND and per-application delivery modes now that
// history is a directory of files. Older versions kept `pending`/`past`
// (and, older still, `entries`) arrays in there; their presence is reported
// so the service can rewrite the file without the dead payload.
function parseSettings(raw) {
  var text = String(raw || "").trim()
  if (!text) return { error: false, dnd: null, modes: {}, legacy: false, future: false }

  try {
    var parsed = JSON.parse(text)
    var version = Number(parsed && parsed.version)
    var future = isFinite(version) && version > 4
    return {
      error: false,
      dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null,
      modes: normalizedApplicationModes(parsed && parsed.modes),
      legacy: !!(parsed && !future && (parsed.version !== 4 || parsed.pending || parsed.past || parsed.entries)),
      future: future
    }
  } catch (e) {
    return { error: true, errorMessage: String(e), dnd: null, modes: {}, legacy: false, future: false }
  }
}

// ---------------------------------------------------- popup persistence
//
// Each on-screen popup is mirrored to its own file under
// ~/.local/state/omarchy/notifications/ so toasts survive shell restarts
// (e.g. the restart `omarchy-update` performs). The file exists exactly as
// long as the popup is on screen: it is written when the toast appears and
// moved into the history/ subdirectory when the toast expires, is dismissed,
// or its action is invoked. History is those moved files, newest last-10.

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
  return imageStem(entry) + ".json"
}

// ---------------------------------------------------- persisted images
//
// A notification's images only exist while it is live: Chromium-family
// senders (all Omarchy web apps) delete their scoped /tmp files on close,
// and image-data hints surface as in-process image:// URLs that die with
// the server object. Persisted entries therefore reference their own
// copies, named by the entry's file stem so cleanup can find them from
// the JSON file name alone.

var PERSISTED_IMAGE_ROLES = ["appIcon", "image"]

function imageStem(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || 0)
}

// The filesystem path behind a file-backed image value, or "" for anything
// a copy can't capture: themed icon names, in-process image:// URLs, empty.
function localImageFile(value) {
  var s = String(value || "")
  if (s.indexOf("file://") === 0) {
    s = s.slice(7)
    try { s = decodeURIComponent(s) } catch (e) {}
  }
  return s.charAt(0) === "/" ? s : ""
}

// The entry as it should hit the disk, plus the copies that make it true.
// File-backed images redirect to their copy under imagesDir; dead image://
// URLs drop to "" (the card falls back to the app icon). Already-redirected
// values map onto themselves and produce no copy, keeping restores no-ops.
function persistablePopup(entry, imagesDir) {
  var e = entry || {}
  var out = {}
  for (var key in e) out[key] = e[key]
  var copies = []
  for (var i = 0; i < PERSISTED_IMAGE_ROLES.length; i++) {
    var role = PERSISTED_IMAGE_ROLES[i]
    var value = String(out[role] || "")
    if (!value) continue
    var source = localImageFile(value)
    if (source) {
      var copy = String(imagesDir || "") + imageStem(e) + "-" + role
      if (source !== copy) copies.push({ from: source, to: copy })
      out[role] = "file://" + copy
    } else if (value.indexOf("image://") === 0) {
      out[role] = ""
    }
  }
  return { entry: out, copies: copies }
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

// The archived files are the history. They are read back exactly like the
// live popup files, then normalized into history rows: replaying a toast
// must not inherit the original's expire timeout or restore deadline, so it
// gets the standard on-screen lifetime for its urgency instead.
//
// liveRows are the toasts still on screen when the replay was asked for.
// They belong in it — they're the newest notifications there are — but the
// directory read races their archival, so they're carried across by hand and
// keyed by file name (timestamp + id) to drop the copy the read already saw.
function historyRows(raw, liveRows, normalUrgency, limit) {
  var max = limit === undefined || limit === null ? 10 : Number(limit)
  if (isNaN(max)) max = 10
  max = Math.max(0, max)

  var out = []
  var seen = {}
  function collect(rows) {
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      if (!entry) continue
      var key = popupFileName(entry)
      if (seen[key]) continue
      seen[key] = true
      out.push(historyEntry(entry, normalUrgency))
    }
  }

  collect(Array.isArray(liveRows) ? liveRows : [])
  collect(parsePopupFiles(raw, normalUrgency))
  out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out.slice(0, max)
}

if (typeof module !== "undefined") {
  module.exports = {
    isChromiumDerived: isChromiumDerived,
    normalizedIdentity: normalizedIdentity,
    applicationKey: applicationKey,
    normalizedOrigin: normalizedOrigin,
    originKey: originKey,
    webAppOrigin: webAppOrigin,
    browserOriginFromBody: browserOriginFromBody,
    notificationSource: notificationSource,
    applicationAlias: applicationAlias,
    buildApplicationCatalog: buildApplicationCatalog,
    validApplicationMode: validApplicationMode,
    normalizedApplicationModes: normalizedApplicationModes,
    deliveryTarget: deliveryTarget,
    sanitizeBody: sanitizeBody,
    summaryStartsWithGlyph: summaryStartsWithGlyph,
    shouldBypassDnd: shouldBypassDnd,
    isEphemeralApp: isEphemeralApp,
    stringHint: stringHint,
    glyphFromHints: glyphFromHints,
    execFromHints: execFromHints,
    shouldRenderCompactGlyph: shouldRenderCompactGlyph,
    snapshotOf: snapshotOf,
    popupRoles: popupRoles,
    popupRowChanged: popupRowChanged,
    replacementSnapshot: replacementSnapshot,
    historyEntry: historyEntry,
    parseSettings: parseSettings,
    historyRows: historyRows,
    popupEntry: popupEntry,
    popupFileName: popupFileName,
    imageStem: imageStem,
    localImageFile: localImageFile,
    persistablePopup: persistablePopup,
    serializePopup: serializePopup,
    parsePopupFiles: parsePopupFiles,
    popupExpired: popupExpired,
    popupPlacement: popupPlacement
  }
}
