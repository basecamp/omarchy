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
  if (entry && typeof entry === "object") {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function layoutHasWidget(layout, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout && layout[sections[s]]
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

function listHas(list, id) {
  return list instanceof Array && list.indexOf(id) !== -1
}

function copyList(list) {
  return list instanceof Array ? list.slice() : []
}

function removeId(list, id) {
  var next = copyList(list)
  var idx = next.indexOf(id)
  if (idx !== -1) next.splice(idx, 1)
  return next
}

function addId(list, id) {
  var next = copyList(list)
  if (next.indexOf(id) === -1) next.push(id)
  return next
}

function itemId(item) {
  if (typeof item === "string") return item
  return String((item && item.id) || "")
}

// hidden > pinned > unpinned > default. The default is the drawer unless
// pinNew is on, in which case unknown (not hidden, not explicitly unpinned)
// items stay visible. unpinned exists so Unpin still works when pinNew is on.
function classifyItem(item, opts) {
  var iid = itemId(item)
  var hidden = (opts && opts.hiddenIds) || []
  var pinned = (opts && opts.pinnedIds) || []
  var unpinned = (opts && opts.unpinnedIds) || []
  var pinNew = !!(opts && opts.pinNew)
  if (listHas(hidden, iid)) return "hidden"
  if (listHas(pinned, iid)) return "pinned"
  if (listHas(unpinned, iid)) return "drawer"
  return pinNew ? "pinned" : "drawer"
}

function togglePin(iid, pinned, unpinned, hidden, pinNew) {
  var opts = { pinnedIds: pinned, unpinnedIds: unpinned, hiddenIds: hidden, pinNew: pinNew }
  if (classifyItem(iid, opts) === "pinned") {
    return {
      pinned: removeId(pinned, iid),
      unpinned: addId(unpinned, iid),
      hidden: copyList(hidden)
    }
  }
  return {
    pinned: addId(pinned, iid),
    unpinned: removeId(unpinned, iid),
    hidden: removeId(hidden, iid)
  }
}

function toggleHide(iid, pinned, unpinned, hidden) {
  if (listHas(hidden, iid)) {
    return {
      pinned: copyList(pinned),
      unpinned: copyList(unpinned),
      hidden: removeId(hidden, iid)
    }
  }
  return {
    pinned: removeId(pinned, iid),
    unpinned: removeId(unpinned, iid),
    hidden: addId(hidden, iid)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    itemNamed: itemNamed,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy,
    classifyItem: classifyItem,
    togglePin: togglePin,
    toggleHide: toggleHide
  }
}
