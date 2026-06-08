function text(value) {
  return String(value || "").toLowerCase()
}

function isDropboxTrayItem(item) {
  if (!item) return false
  return text(item.id).indexOf("dropbox") !== -1
    || text(item.title).indexOf("dropbox") !== -1
    || text(item.tooltipTitle).indexOf("dropbox") !== -1
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

function ownedByDedicatedWidget(item, layout) {
  return layoutHasWidget(layout, "omarchy.dropbox") && isDropboxTrayItem(item)
}

if (typeof module !== "undefined") {
  module.exports = {
    isDropboxTrayItem: isDropboxTrayItem,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByDedicatedWidget: ownedByDedicatedWidget
  }
}
