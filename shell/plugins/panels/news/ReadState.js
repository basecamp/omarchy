function isRead(item, items, readIds, checkpoints) {
  if (readIds.indexOf(String(item.id || "")) >= 0) return true
  var checkpoint = String(checkpoints[String(item.sourceId || "omarchy")] || "")
  if (!checkpoint) return false
  var reached = false
  for (var i = 0; i < items.length; i++) {
    if (items[i].sourceId !== item.sourceId) continue
    if (String(items[i].id) === checkpoint) reached = true
    if (String(items[i].id) === String(item.id)) return reached
  }
  return false
}

function mark(readIds, id) {
  id = String(id || "")
  if (!id || readIds.indexOf(id) >= 0) return readIds
  return readIds.concat([id]).slice(-4096)
}

if (typeof module !== "undefined") module.exports = { isRead: isRead, mark: mark }
