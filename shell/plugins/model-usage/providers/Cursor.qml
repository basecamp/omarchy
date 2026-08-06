import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property string providerId: "cursor"
  property string providerName: "Cursor"
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
  property string authHelpText: "Open Cursor and sign in."
  property bool hasLocalStats: true

  property string configModel: ""
  property var providerSettings: ({})

  readonly property string scannerPath: String(Qt.resolvedUrl("../scripts/cursor_usage_scanner.py")).replace("file://", "")

  function resolvePath(value) {
    const text = String(value || "").trim()
    if (text === "")
      return ""
    if (text.startsWith("~/"))
      return (Quickshell.env("HOME") || "") + text.slice(1)
    if (text === "~")
      return Quickshell.env("HOME") || ""
    return text
  }

  function scannerCommand() {
    const command = ["python3", root.scannerPath]
    const stateDb = root.resolvePath(root.providerSettings?.stateDbPath ?? "")
    if (stateDb !== "")
      command.push("--state-db", stateDb)
    return command
  }

  Process {
    id: usageScanner
    command: root.scannerCommand()
    running: false

    stdout: StdioCollector {
      onStreamFinished: root.parseScannerOutput(text)
    }

    onExited: root.finishRefresh()

    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("model-usage/cursor", text.trim())
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
    if (usageScanner.running)
      return
    root.refreshing = true
    usageScanner.command = root.scannerCommand()
    usageScanner.running = true
  }

  function refreshLimits() { refresh() }

  function parseScannerOutput(output) {
    const raw = String(output || "").trim()
    if (raw === "")
      return

    try {
      const data = JSON.parse(raw.split("\n").pop())
      root.ready = !!data.ready
      root.hasLocalStats = data.hasLocalStats !== false

      root.rateLimitPercent = data.rateLimitPercent ?? -1
      root.rateLimitLabel = data.rateLimitLabel || ""
      root.rateLimitResetAt = data.rateLimitResetAt || ""
      root.secondaryRateLimitPercent = data.secondaryRateLimitPercent ?? -1
      root.secondaryRateLimitLabel = data.secondaryRateLimitLabel || ""
      root.secondaryRateLimitResetAt = data.secondaryRateLimitResetAt || ""

      root.tierLabel = data.tierLabel || ""
      root.usageStatusText = data.usageStatusText || ""
      root.authHelpText = data.authHelpText || "Open Cursor and sign in."

      // Period pools only — keep history fields empty so chart sections stay hidden.
      root.todayPrompts = 0
      root.todaySessions = 0
      root.todayTotalTokens = 0
      root.todayTokensByModel = ({})
      root.recentDays = []
      root.totalPrompts = 0
      root.totalSessions = 0
      root.activeDays = 0
      root.activeDates = []
      root.modelUsage = ({})
    } catch (e) {
      console.error("model-usage/cursor", "Failed to parse scanner output:", e, raw)
      root.usageStatusText = "Cursor scan failed"
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
