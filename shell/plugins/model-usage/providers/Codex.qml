import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property string providerId: "codex"
  property string providerName: "Codex"
  property string providerIcon: "ai"
  property bool enabled: false
  property bool ready: false
  property bool refreshing: false
  property double lastRefreshedAtMs: 0

  property real rateLimitPercent: -1
  property string rateLimitLabel: ""
  property string rateLimitResetAt: ""
  property real secondaryRateLimitPercent: -1
  property string secondaryRateLimitLabel: ""
  property string secondaryRateLimitResetAt: ""

  property int todayPrompts: 0
  property int todaySessions: 0
  property real todayTotalTokens: 0
  property var todayTokensByModel: ({})

  property var recentDays: []
  property int totalPrompts: 0
  property int totalSessions: 0
  property int activeDays: 0
  property var activeDates: []
  property var modelUsage: ({})

  property string tierLabel: ""
  property string usageStatusText: ""
  // Optimistic until the probe answers, so a present provider never blinks
  // out of the panel on startup.
  property bool installed: true
  property string authHelpText: "Run `codex login` to authenticate."
  property bool hasLocalStats: true

  property string configModel: ""
  property var providerSettings: ({})

  readonly property string scannerPath: String(Qt.resolvedUrl("../scripts/codex_usage_scanner.py")).replace("file://", "")

  // Codex is "here" if its state directory, its session store, or the CLI
  // exists. Re-runs on refresh so installing it mid-session shows up.
  Process {
    id: presenceProbe
    running: true
    command: ["bash", "-c", "[[ -d \"$HOME/.codex\" ]] || [[ -d \"$HOME/.pi/agent/sessions\" ]] || command -v codex >/dev/null"]
    onExited: function (exitCode) {
      root.installed = exitCode === 0
    }
  }

  Process {
    id: usageScanner
    command: ["python3", root.scannerPath]
    running: false

    stdout: StdioCollector {
      onStreamFinished: root.parseScannerOutput(text)
    }

    onExited: root.finishRefresh()

    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("model-usage/codex", text.trim())
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onEnabledChanged: if (enabled) refresh()

  function finishRefresh() {
    root.refreshing = false
    root.lastRefreshedAtMs = Date.now()
  }

  function refresh(force) {
    if (!presenceProbe.running)
      presenceProbe.running = true
    if (usageScanner.running)
      return
    root.refreshing = true
    usageScanner.running = true
  }

  function parseScannerOutput(output) {
    const raw = String(output || "").trim()
    if (raw === "")
      return

    try {
      const data = JSON.parse(raw.split("\n").pop())
      root.ready = !!data.ready
      root.hasLocalStats = data.hasLocalStats !== false

      root.todayPrompts = data.todayPrompts || 0
      root.todaySessions = data.todaySessions || 0
      root.todayTotalTokens = data.todayTotalTokens || 0
      root.todayTokensByModel = data.todayTokensByModel || ({})
      root.recentDays = data.recentDays || []
      root.totalPrompts = data.totalPrompts || 0
      root.totalSessions = data.totalSessions || 0
      root.activeDays = data.activeDays || 0
      root.activeDates = data.activeDates || []
      root.modelUsage = data.modelUsage || ({})

      root.rateLimitPercent = data.rateLimitPercent ?? -1
      root.rateLimitLabel = data.rateLimitLabel || ""
      root.rateLimitResetAt = data.rateLimitResetAt || ""
      root.secondaryRateLimitPercent = data.secondaryRateLimitPercent ?? -1
      root.secondaryRateLimitLabel = data.secondaryRateLimitLabel || ""
      root.secondaryRateLimitResetAt = data.secondaryRateLimitResetAt || ""

      root.tierLabel = data.tierLabel || ""
      root.usageStatusText = data.usageStatusText || ""
      root.authHelpText = data.authHelpText || "Run `codex login` to authenticate."
    } catch (e) {
      console.error("model-usage/codex", "Failed to parse scanner output:", e, raw)
      root.usageStatusText = "Codex scan failed"
      root.authHelpText = String(e)
      root.ready = true
    }
  }

  function formatResetTime(isoTimestamp) {
    if (!isoTimestamp)
      return ""
    const reset = new Date(isoTimestamp)
    const now = new Date()
    const diffMs = reset.getTime() - now.getTime()
    if (diffMs <= 0)
      return "now"
    const hours = Math.floor(diffMs / 3600000)
    const mins = Math.floor((diffMs % 3600000) / 60000)
    if (hours > 24)
      return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
    if (hours > 0)
      return hours + "h " + mins + "m"
    return mins + "m"
  }
}
