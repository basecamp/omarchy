
function advancePhase(phase, completedSessions, sessionsBeforeLongBreak, completed) {
  if (phase === "custom") {
    return "focus"
  }
  if (phase === "focus") {
    if (completed && completedSessions > 0 && completedSessions % sessionsBeforeLongBreak === 0) {
      return "longBreak"
    }
    return "shortBreak"
  }
  return "focus"
}

function getPhaseSecs(phase, focusSecs, shortBreakSecs, longBreakSecs, customMinutes) {
  if (phase === "focus") return focusSecs
  if (phase === "shortBreak") return shortBreakSecs
  if (phase === "longBreak") return longBreakSecs
  if (phase === "custom") return customMinutes * 60
  return focusSecs
}

// Ensure Node.js can require this for testing
if (typeof module !== 'undefined') {
  module.exports = { advancePhase, getPhaseSecs }
}
