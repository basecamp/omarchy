// Rows for the add-widget picker: every installed bar widget that is not
// already on the bar, described the way its manifest presents itself.
function pickerRows(installedPlugins, onBarIds) {
  var onBar = {}
  var ids = Array.isArray(onBarIds) ? onBarIds : []
  for (var i = 0; i < ids.length; i++) onBar[String(ids[i])] = true

  var rows = []
  var plugins = installedPlugins || {}
  for (var id in plugins) {
    var manifest = plugins[id]
    if (!manifest || !Array.isArray(manifest.kinds) || manifest.kinds.indexOf("bar-widget") === -1) continue
    if (onBar[id]) continue

    var meta = manifest.barWidget && typeof manifest.barWidget === "object" ? manifest.barWidget : {}
    rows.push({
      id: String(id),
      name: String(meta.displayName || manifest.name || id),
      description: String(meta.description || manifest.description || ""),
      category: String(meta.category || "Other")
    })
  }

  rows.sort(function(a, b) {
    if (a.category !== b.category) return a.category < b.category ? -1 : 1
    if (a.name !== b.name) return a.name < b.name ? -1 : 1
    return a.id < b.id ? -1 : 1
  })
  return rows
}

// Case-insensitive substring match on anything the user can see, plus the id
// they may know from the CLI.
function filterRows(rows, filterText) {
  var needle = String(filterText || "").trim().toLowerCase()
  var values = Array.isArray(rows) ? rows : []
  if (!needle) return values

  return values.filter(function(row) {
    var haystack = row.name + " " + row.id + " " + row.category + " " + row.description
    return haystack.toLowerCase().indexOf(needle) !== -1
  })
}

// The placement a bar right-click hands over, reduced to the keys
// putBarWidget understands. Anything else in the payload is dropped so a
// stray field can never reach the config mutation.
function parsePlacement(payloadJson) {
  var payload = {}
  try {
    payload = JSON.parse(String(payloadJson || "{}")) || {}
  } catch (e) {
    payload = {}
  }

  var placement = {}
  if (payload.section) placement.section = String(payload.section)
  if (payload.before) placement.before = String(payload.before)
  else if (payload.after) placement.after = String(payload.after)
  else if (isFinite(Number(payload.index)) && payload.index !== null && payload.index !== "")
    placement.index = Math.max(0, Math.floor(Number(payload.index)))
  return { placement: placement, screen: String(payload.screen || "") }
}

if (typeof module !== "undefined") {
  module.exports = {
    pickerRows: pickerRows,
    filterRows: filterRows,
    parsePlacement: parsePlacement
  }
}
