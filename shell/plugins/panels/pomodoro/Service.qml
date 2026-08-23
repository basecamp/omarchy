import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var settings: ({})

  function setting(name, fallback, min, max) {
    var value = settings ? settings[name] : undefined
    value = value === undefined || value === null ? fallback : value
    if (min !== undefined) value = Math.max(min, value)
    if (max !== undefined) value = Math.min(max, value)
    return value
  }

  readonly property int focusSecs: setting("focusMinutes", 25, 1, 120) * 60
  readonly property int shortBreakSecs: setting("shortBreakMinutes", 5, 1, 60) * 60
  readonly property int longBreakSecs: setting("longBreakMinutes", 15, 1, 120) * 60
  readonly property int sessionsBeforeLong: setting("sessionsBeforeLongBreak", 4, 1, 10)

  onFocusSecsChanged: { if (!running && phase === "focus") { totalSecs = focusSecs; remainingSecs = focusSecs; } }
  onShortBreakSecsChanged: { if (!running && phase === "shortBreak") { totalSecs = shortBreakSecs; remainingSecs = shortBreakSecs; } }
  onLongBreakSecsChanged: { if (!running && phase === "longBreak") { totalSecs = longBreakSecs; remainingSecs = longBreakSecs; } }

  property string phase: "focus"
  property int totalSecs: focusSecs
  property int remainingSecs: focusSecs
  property bool running: false
  property int completedSessions: 0
  property int customMinutes: 10

  property double targetTimeMs: 0
  
  // Human-readable helpers
  readonly property string phaseLabel: phase === "focus" ? "Focus"
    : phase === "shortBreak" ? "Short Break"
    : phase === "longBreak" ? "Long Break"
    : "Custom Timer"

  readonly property string timeText: {
    var m = Math.floor(remainingSecs / 60)
    var s = remainingSecs % 60
    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  readonly property real progress: totalSecs > 0
    ? 1.0 - (remainingSecs / totalSecs) : 0

  readonly property bool alarming: running && remainingSecs <= 30

  function start(duration) {
    if (!running) {
      if (duration) {
        remainingSecs = duration
        totalSecs = duration
      }
      targetTimeMs = Date.now() + (remainingSecs * 1000)
      running = true
    }
  }

  function pause() {
    running = false
  }

  function skip() {
    running = false
    advancePhase(false)
  }

  function reset() {
    running = false
    phase = "focus"
    completedSessions = 0
    totalSecs = focusSecs
    remainingSecs = focusSecs
  }

  function setCustom(mins) {
    running = false
    customMinutes = mins
    phase = "custom"
    totalSecs = mins * 60
    remainingSecs = mins * 60
    start(0)
  }

  function advancePhase(completed) {
    var previousPhase = phase
    if (completed && phase === "focus") {
      completedSessions++
    }
    phase = Model.advancePhase(previousPhase, completedSessions, sessionsBeforeLong, completed)
    totalSecs = Model.getPhaseSecs(phase, focusSecs, shortBreakSecs, longBreakSecs, customMinutes)
    remainingSecs = totalSecs
  }

  Process {
    id: alarmSound
    command: ["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]
  }

  Process {
    id: notifyProcess
    property string titleMsg: ""
    property string bodyMsg: ""
    command: ["omarchy-notification-send", titleMsg, bodyMsg]
  }

  function onPhaseComplete() {
    running = false
    
    notifyProcess.titleMsg = phase === "focus" ? "Focus complete" : (phase === "custom" ? "Timer complete" : "Break complete")
    notifyProcess.bodyMsg = phase === "focus" ? "Time for a break." : (phase === "custom" ? "Your custom timer has elapsed." : "Back to work!")
    
    alarmSound.running = true
    notifyProcess.running = true
    
    advancePhase(true)
  }

  Timer {
    id: countdown
    interval: 500
    running: root.running
    repeat: true
    onTriggered: {
      if (root.running) {
        var now = Date.now()
        var rem = Math.ceil(Math.max(0, root.targetTimeMs - now) / 1000)
        root.remainingSecs = rem
        if (rem <= 0) {
          root.onPhaseComplete()
        }
      }
    }
  }
}
