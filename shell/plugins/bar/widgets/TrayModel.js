var SECTIONS = ["left", "center", "right"]

function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object" && !Array.isArray(entry)) {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function entrySettings(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) return {}
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

function layoutHasWidget(layout, id) {
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout && layout[SECTIONS[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
}

// LocalSend's item shows no state, offers only Open and Quit, and its primary
// click is a no-op, so Share > Receive is the whole surface. Hiding it by hand
// doesn't stick either: LocalSend picks a fresh tray id every launch.
function ownedByOmarchy(item, layout) {
  return itemNamed(item, "localsend")
    || (layoutHasWidget(layout, "omarchy.dropbox") && itemNamed(item, "dropbox"))
}

// QML can hand a settings array across property boundaries as a variant-list
// proxy: typeof "object", instanceof Array, but Array.isArray false and array
// methods missing. Which form arrives depends on the injection path, so every
// settings-derived list must be copied into a real array before use.
function asList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number") {
    var out = []
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }
  return []
}

// The `widgets` setting holds one wrapper per captured bar widget:
//   { entry: <original layout entry> }
// Tolerate hand-edited shorthand (a bare id string, or a bare entry object)
// so a typo'd shell.json degrades to defaults instead of a dead tray.
function normalizeWrappers(raw) {
  var out = []
  var values = asList(raw)
  for (var i = 0; i < values.length; i++) {
    var wrapper = values[i]
    if (!wrapper) continue
    if (typeof wrapper === "string") {
      out.push({ entry: { id: wrapper } })
      continue
    }
    if (wrapper.entry && entryId(wrapper.entry)) {
      out.push({ entry: wrapper.entry })
      continue
    }
    if (entryId(wrapper)) out.push({ entry: wrapper })
  }
  return out
}

function wrapperId(wrapper) {
  if (!wrapper) return ""
  return wrapper.entry ? entryId(wrapper.entry) : entryId(wrapper)
}

// The shell loads a third-party plugin's widget component only while its id
// is referenced in shell.json (bar.id, a bar.layout entry, or plugins[]).
// A captured widget's id lives inside the tray's settings, which that scan
// does not see, so without a plugins[] entry the shell unloads the component
// and the hosted widget renders as nothing. Returns true when an entry was
// added (i.e. the tray owns it and must remove it again on release).
function ensurePluginListed(config, id) {
  if (!Array.isArray(config.plugins)) config.plugins = []
  for (var i = 0; i < config.plugins.length; i++) {
    var e = config.plugins[i]
    var eid = typeof e === "string" ? e : (e ? String(e.id || "") : "")
    if (eid === id) return false
  }
  config.plugins.push({ id: id })
  return true
}

function unlistPlugin(config, id) {
  if (!Array.isArray(config.plugins)) return
  config.plugins = config.plugins.filter(function(e) {
    if (!e) return false
    var eid = typeof e === "string" ? e : String(e.id || "")
    return eid !== id
  })
}

function findLayoutEntry(layout, id) {
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout ? layout[SECTIONS[s]] : null
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) {
        return { section: SECTIONS[s], entries: entries, index: i, entry: entries[i] }
      }
    }
  }
  return null
}

// Mutates `config` in place: pull `sourceId`'s entry out of the bar layout
// and append it to the tray entry's `widgets` list. `orderTokens`, when
// given, becomes the tray's drawer order — the caller computes it from the
// drop position so a dragged-in widget lands exactly where it was released.
// Returns true when anything moved.
function captureIntoTray(config, trayId, sourceId, orderTokens) {
  if (!sourceId || sourceId === trayId) return false
  var layout = config && config.bar ? config.bar.layout : null
  if (!layout) return false

  var source = findLayoutEntry(layout, sourceId)
  if (!source) return false
  source.entries.splice(source.index, 1)

  // Resolve the tray entry only after the splice: both can live in the same
  // section array, and an index recorded before the removal would be stale.
  var tray = findLayoutEntry(layout, trayId)
  if (!tray) {
    source.entries.splice(source.index, 0, source.entry)
    return false
  }

  var trayEntry = tray.entry
  if (typeof trayEntry === "string") {
    trayEntry = { id: trayEntry }
    tray.entries[tray.index] = trayEntry
  }
  if (!Array.isArray(trayEntry.widgets)) trayEntry.widgets = []
  var entry = typeof source.entry === "string" ? { id: source.entry } : source.entry
  var wrapper = { entry: entry }
  // Keep the plugin loaded while its only reference is inside the tray.
  if (ensurePluginListed(config, sourceId)) wrapper.listed = true
  trayEntry.widgets.push(wrapper)
  if (Array.isArray(orderTokens) && orderTokens.length) trayEntry.order = orderTokens.map(String)
  return true
}

// Remove `widgetId`'s wrapper from a tray entry (widgets + pinnedWidgets)
// and return it, or null when it isn't hosted there.
function takeWrapper(trayEntry, widgetId) {
  var wrappers = Array.isArray(trayEntry.widgets) ? trayEntry.widgets : []
  var index = -1
  for (var i = 0; i < wrappers.length; i++) {
    if (wrapperId(wrappers[i]) === widgetId) { index = i; break }
  }
  if (index === -1) return null
  var wrapper = wrappers.splice(index, 1)[0]
  if (wrappers.length === 0) delete trayEntry.widgets
  if (Array.isArray(trayEntry.order)) {
    trayEntry.order = trayEntry.order.filter(function(token) { return String(token) !== widgetId })
    if (trayEntry.order.length === 0) delete trayEntry.order
  }
  return wrapper
}

function indexOfEntry(entries, id) {
  for (var i = 0; i < entries.length; i++) {
    if (entryId(entries[i]) === id) return i
  }
  return -1
}

// Drop a hosted widget back into the bar layout at an explicit position —
// the drag-out counterpart of captureIntoTray. Inserts before `beforeName`
// in `toRegion`, or at the section's end when beforeName is empty or gone.
function dragOutOfTray(config, trayId, widgetId, toRegion, beforeName) {
  var layout = config && config.bar ? config.bar.layout : null
  if (!layout) return false

  var tray = findLayoutEntry(layout, trayId)
  if (!tray || typeof tray.entry === "string") return false
  var wrapper = takeWrapper(tray.entry, widgetId)
  if (!wrapper) return false
  // Back in the layout, the entry itself keeps the plugin loaded again.
  if (wrapper.listed) unlistPlugin(config, widgetId)

  var entry = wrapper && wrapper.entry ? wrapper.entry : wrapper
  var region = SECTIONS.indexOf(toRegion) !== -1 ? toRegion : "right"
  if (!Array.isArray(layout[region])) layout[region] = []
  var target = layout[region]
  var index = beforeName ? indexOfEntry(target, String(beforeName)) : -1
  if (index < 0) target.push(entry)
  else target.splice(index, 0, entry)
  return true
}

// Sort drawer content by the persisted `order` token list. Works on anything
// carrying a `key` (mixed drawer entries) or an `id` (raw status-notifier
// items). Tokens not in the list keep their arrival order, after every
// ordered one, so new content appears at the end instead of shuffling the
// arranged pieces.
function orderKey(item) {
  if (!item) return ""
  if (item.key !== undefined) return String(item.key)
  return String(item.id || "")
}

function sortByOrder(items, order) {
  var ord = asList(order).map(String)
  var decorated = []
  for (var i = 0; i < items.length; i++) decorated.push({ item: items[i], index: i })
  decorated.sort(function(a, b) {
    var ai = ord.indexOf(orderKey(a.item))
    var bi = ord.indexOf(orderKey(b.item))
    var ak = ai === -1 ? ord.length + a.index : ai
    var bk = bi === -1 ? ord.length + b.index : bi
    return ak - bk
  })
  return decorated.map(function(e) { return e.item })
}

// Move `id` within an id list so it sits before `beforeId` ("" = end).
// Returns the new array, or null when the order would not change.
function movedBefore(order, id, beforeId) {
  var ids = asList(order).map(String)
  var from = ids.indexOf(String(id))
  if (from === -1) return null
  ids.splice(from, 1)
  var to = beforeId ? ids.indexOf(String(beforeId)) : ids.length
  if (to === -1) to = ids.length
  if (to === from) return null
  ids.splice(to, 0, String(id))
  return ids
}

if (typeof module !== "undefined") {
  module.exports = {
    asList: asList,
    ensurePluginListed: ensurePluginListed,
    unlistPlugin: unlistPlugin,
    itemNamed: itemNamed,
    entryId: entryId,
    entrySettings: entrySettings,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy,
    normalizeWrappers: normalizeWrappers,
    wrapperId: wrapperId,
    findLayoutEntry: findLayoutEntry,
    captureIntoTray: captureIntoTray,
    dragOutOfTray: dragOutOfTray,
    sortByOrder: sortByOrder,
    movedBefore: movedBefore
  }
}
