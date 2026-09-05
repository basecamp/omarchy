// Model math for the workspace row, kept Qt-free so it can be unit tested under
// node (test/shell.d/workspaces-model-test.sh).

// The row always offers 1-5, plus any other workspace up to 10 that exists.
function workspaceIds(values) {
  var ids = [1, 2, 3, 4, 5]
  var list = values || []

  for (var i = 0; i < list.length; i++) {
    var id = list[i] && list[i].id
    if (typeof id !== "number" || !isFinite(id)) continue
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  ids.sort(function(left, right) { return left - right })
  return ids
}

// A Repeater compares its model by identity, not by contents: hand it a new
// array and it destroys every delegate and builds them again, however alike the
// two arrays are. The row's model used to be a function call, allocating a fresh
// array on every evaluation, and the binding re-ran whenever Hyprland created or
// destroyed a workspace.
//
// That is exactly what switching to an empty workspace does. Moving between
// workspaces that hold windows leaves the list alone and was smooth; pressing
// SUPER+4 from an occupied workspace created 4 and rebuilt the whole row, then
// destroyed it on the way out and rebuilt it again -- which is why the stutter
// came and went rather than being there every time.
//
// So the caller keeps its array and only replaces it when the ids really
// changed. Returns the array to keep, which is the old one whenever it still
// describes the same row.
function stableIds(previous, next) {
  var before = previous || []

  if (before.length === next.length) {
    for (var i = 0; i < next.length; i++) {
      if (before[i] !== next[i]) return next
    }

    return before
  }

  return next
}

// Built once per change rather than scanned inside each delegate, which made
// drawing the row cost O(n^2) every time it was rebuilt.
function byId(values) {
  var map = ({})
  var list = values || []

  for (var i = 0; i < list.length; i++) {
    var workspace = list[i]
    if (workspace && typeof workspace.id === "number") map[workspace.id] = workspace
  }

  return map
}

if (typeof module !== "undefined") {
  module.exports = {
    byId: byId,
    stableIds: stableIds,
    workspaceIds: workspaceIds
  }
}
