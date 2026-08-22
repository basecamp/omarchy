import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Display state for the backup panel, read from the file omarchy-backup-run
// maintains. Nothing here shells out to restic: a panel that queried the
// repository would be slow to open, and would touch the repository every time
// someone glanced at the bar.
Item {
  id: root

  property var settings: ({})
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/backup"
  readonly property string statusPath: stateDir + "/status.json"

  property var status: Model.defaultStatus()
  property double nowMs: Date.now()

  // Optimistic pause state, so the button reacts on the click rather than after
  // the CLI has written the file back. -1 follows reality; 0/1 override it.
  property int _desiredPause: -1

  readonly property string phase: String(status.phase || "unconfigured")
  readonly property bool configured: phase !== "unconfigured"
  readonly property bool running: phase === "running"
  readonly property bool paused: _desiredPause === -1 ? phase === "paused" : _desiredPause === 1
  readonly property int staleAfterHours: intSetting("staleAfterHours", 24, 2, 168)
  readonly property bool attention: Model.attention(status, staleAfterHours, nowMs)
  readonly property string heroMeta: Model.heroMeta(status, staleAfterHours, nowMs)
  readonly property string repositoryText: Model.repositoryText(status)
  readonly property string progressText: Model.progressText(status)
  readonly property string problem: Model.problem(status)
  readonly property int percent: Number(status.progress.percent || 0)
  readonly property var snapshots: status.snapshots || []
  readonly property bool offsite: status.destination.offsite !== false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var parsed = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(parsed)) parsed = fallback
    return Math.max(min, Math.min(max, parsed))
  }

  function apply(text) {
    status = Model.parseStatus(text)
    if (_desiredPause !== -1 && (phase === "paused") === (_desiredPause === 1)) _desiredPause = -1
  }

  function backUpNow() {
    if (!configured || running) return
    Quickshell.execDetached(["omarchy-backup-now"])
  }

  function pause(duration) {
    if (!configured) return
    _desiredPause = 1
    Quickshell.execDetached(["omarchy-backup-pause", duration])
  }

  function resume() {
    if (!configured) return
    _desiredPause = 0
    Quickshell.execDetached(["omarchy-backup-resume"])
  }

  // Restores and browsing print, confirm, and can take a while, so they belong
  // in a terminal rather than behind a panel button that shows nothing.
  function browse() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-backup-browse"])
  }

  function setUp() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-setup-backup"])
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: root.status = Model.defaultStatus()
  }

  // The runner replaces status.json by rename rather than writing into it, and
  // FileView loses a file that is replaced. Watching the directory it lives in
  // is what makes the panel notice the new one.
  FileView {
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: statusFile.reload()
  }

  // Relative times ("12 minutes ago") and the pause countdown go stale on their
  // own, with no file change to trigger a repaint.
  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }
}
