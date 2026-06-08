function validMinutes(value) {
  var minutes = String(value || "").trim()
  return /^[0-9]+$/.test(minutes) && Number(minutes) > 0 ? minutes : ""
}

function reminderArgs(minutes, message) {
  var valid = validMinutes(minutes)
  if (!valid) return []

  var args = [valid]
  var text = String(message || "")
  if (text.length > 0) args.push(text)
  return args
}

if (typeof module !== "undefined") {
  module.exports = {
    validMinutes: validMinutes,
    reminderArgs: reminderArgs
  }
}
