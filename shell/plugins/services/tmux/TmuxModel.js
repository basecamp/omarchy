// Shape of `omarchy-tmux-alert show --json`. The command emits one JSON object
// on the last line; anything tmux or a shell profile printed before it is
// ignored so a noisy environment cannot blank the indicator.
function waitingFromOutput(output) {
  var text = String(output === undefined || output === null ? "" : output).trim()
  if (!text) return { count: 0, tooltip: "" }

  var lines = text.split("\n")
  var data
  try {
    data = JSON.parse(lines[lines.length - 1])
  } catch (e) {
    return { count: 0, tooltip: "" }
  }

  if (!data || typeof data !== "object") return { count: 0, tooltip: "" }

  var count = Number(data.count)
  return {
    count: isFinite(count) && count > 0 ? Math.floor(count) : 0,
    tooltip: data.tooltip === undefined || data.tooltip === null ? "" : String(data.tooltip)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    waitingFromOutput: waitingFromOutput
  }
}
