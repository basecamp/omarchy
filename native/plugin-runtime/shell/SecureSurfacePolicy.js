function liveScreenNames(values) {
  var names = []
  for (var index = 0; index < values.length; index++) {
    var name = String(values[index] || "")
    if (name !== "" && names.indexOf(name) === -1) names.push(name)
  }
  return names
}

function chooseOwner(values, focusedName, currentOwner, hasEntries) {
  if (!hasEntries) return ""
  var names = liveScreenNames(values)
  var current = String(currentOwner || "")
  if (names.indexOf(current) !== -1) return current
  var focused = String(focusedName || "")
  if (names.indexOf(focused) !== -1) return focused
  return names.length > 0 ? names[0] : ""
}

function chooseOpenScreen(values, focusedName) {
  var names = liveScreenNames(values)
  var focused = String(focusedName || "")
  return names.indexOf(focused) !== -1 ? focused : (names.length > 0 ? names[0] : "")
}
