// Workspace list and window-occupancy math for the workspaces widget,
// kept Qt-free so it can be unit tested under node (test/shell.d/workspaces-test.sh).

function workspaceIds(workspaces) {
  var ids = [1, 2, 3, 4, 5]
  var values = workspaces || []

  for (var i = 0; i < values.length; i++) {
    var id = values[i].id
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  ids.sort(function (left, right) { return left - right })
  return ids
}

function workspaceById(workspaces, id) {
  var values = workspaces || []
  for (var i = 0; i < values.length; i++) {
    if (values[i].id === id) return values[i]
  }
  return null
}

// Focused workspace is the filled-square nerd glyph; workspace 10 is labelled 0
// to match the Super+0 binding.
function workspaceLabel(id, focused) {
  if (focused) return "\uDB85\uDCFB"
  if (id === 10) return "0"
  return String(id)
}

function toplevelList(workspace) {
  if (!workspace || !workspace.toplevels) return []
  var values = workspace.toplevels.values
  if (values && typeof values.length === "number") return values
  if (typeof workspace.toplevels.length === "number") return workspace.toplevels
  return []
}

function toplevelCount(workspace) {
  return toplevelList(workspace).length
}

function isOccupied(workspace) {
  return toplevelCount(workspace) > 0
}

function isWindowFocused(toplevel) {
  return !!(toplevel && toplevel.activated)
}

function windowRowLength(count, square, gap) {
  var n = Number(count)
  if (!isFinite(n) || n <= 0) return 0
  var size = Number(square)
  var spacing = Number(gap)
  if (!isFinite(size) || size < 0) size = 0
  if (!isFinite(spacing) || spacing < 0) spacing = 0
  return n * size + (n - 1) * spacing
}

if (typeof module !== "undefined") {
  module.exports = {
    workspaceIds: workspaceIds,
    workspaceById: workspaceById,
    workspaceLabel: workspaceLabel,
    toplevelList: toplevelList,
    toplevelCount: toplevelCount,
    isOccupied: isOccupied,
    isWindowFocused: isWindowFocused,
    windowRowLength: windowRowLength
  }
}
