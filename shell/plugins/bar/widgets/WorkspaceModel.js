// Holds the workspace widget's id list between evaluations. The Repeater's
// model is a JS array, and QML treats a replaced array as a full model reset,
// tearing down and rebuilding every delegate. Any workspace signal (a toplevel
// arriving, focus moving) re-evaluates the model binding, so without a cache
// the whole row rebuilt on every such event. Returning the same array
// reference while the id set is unchanged keeps the delegates alive; the
// array is only replaced when the set actually differs.

// Qt-free so it can be unit tested under node like the other widget models.
// The cache lives here rather than in a QML property so the model binding
// never reads or writes its own dependency (which QML flags as a binding loop).

var cached = null

function sync(values) {
  var ids = [1, 2, 3, 4, 5]
  for (var i = 0; i < values.length; i++) {
    var id = values[i].id
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  ids.sort(function(left, right) { return left - right })

  if (cached === null) {
    cached = ids
    return cached
  }

  if (ids.length !== cached.length) {
    cached = ids
    return cached
  }

  for (var j = 0; j < ids.length; j++) {
    if (ids[j] !== cached[j]) {
      cached = ids
      return cached
    }
  }

  return cached
}

if (typeof module !== "undefined") {
  module.exports = {
    sync: sync
  }
}
