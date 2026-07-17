import QtQuick
import Quickshell
import Quickshell.Io
import "providers"

Item {
  id: root
  visible: false

  property var settings: ({})

  Claude {
    id: claudeProvider
    enabled: root.providerEnabled("claude")
    providerSettings: root.settings && root.settings.providers && root.settings.providers.claude ? root.settings.providers.claude : ({})
    onLastRefreshedAtMsChanged: root.scheduleSync()
    onReadyChanged: root.scheduleSync()
  }

  Codex {
    id: codexProvider
    enabled: root.providerEnabled("codex")
    providerSettings: root.settings && root.settings.providers && root.settings.providers.codex ? root.settings.providers.codex : ({})
    onLastRefreshedAtMsChanged: root.scheduleSync()
    onReadyChanged: root.scheduleSync()
  }

  property var providers: [claudeProvider, codexProvider]
  property var enabledProviders: {
    var rev = syncRevision
    var running = syncRunning
    var result = []
    if (claudeProvider.enabled) result.push(displayProvider(claudeProvider))
    if (codexProvider.enabled) result.push(displayProvider(codexProvider))
    return result
  }

  property int activeIndex: 0
  property var activeProvider: enabledProviders.length > 0 ? enabledProviders[Math.min(activeIndex, enabledProviders.length - 1)] : null
  property bool refreshing: claudeProvider.refreshing || codexProvider.refreshing || syncRunning
  property double aggregateUpdatedAtMs: aggregateData && aggregateData.updatedAtMs ? Number(aggregateData.updatedAtMs) : 0
  property double lastRefreshedAtMs: Math.max(aggregateUpdatedAtMs, claudeProvider.lastRefreshedAtMs || 0, codexProvider.lastRefreshedAtMs || 0)
  property string barDisplayMode: setting("barDisplayMode", "active")
  property int barCycleIntervalSec: Math.max(1, Number(setting("barCycleIntervalSec", 5)))
  property string barMetric: setting("barMetric", "prompts")
  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 900)))

  property var syncModeSetting: setting("syncMode", setting("syncEnabled", false))
  property bool syncEnabled: parseSyncEnabled(syncModeSetting)
  property string syncDir: String(setting("syncDir", ""))
  property string syncFileName: String(setting("syncFileName", ""))
  property string syncDeviceId: String(setting("syncDeviceId", ""))
  readonly property string home: Quickshell.env("HOME") || ""
  property string detectedHostname: ""
  readonly property string syncEffectiveDir: expandPath(syncDir)
  readonly property string syncEffectiveFileName: safeSnapshotFileName(syncFileName, syncDeviceId)
  readonly property string syncEffectiveDeviceId: safeDeviceId(syncDeviceId || syncEffectiveFileName.replace(/\.json$/i, ""))
  readonly property string syncSnapshotPath: syncConfigured() ? syncEffectiveDir + "/" + syncEffectiveFileName : home + "/.cache/omarchy/model-usage-disabled.json"
  property var aggregateData: ({})
  property int syncRevision: 0
  property bool syncRunning: false
  property bool syncRequestedWhileRunning: false
  property string syncStatusText: ""
  property int syncDeviceCount: syncConfigured() && aggregateData && aggregateData.deviceCount ? Number(aggregateData.deviceCount) : 0

  onSyncEnabledChanged: syncSettingsChanged()
  onSyncDirChanged: syncSettingsChanged()
  onSyncFileNameChanged: if (syncConfigured()) scheduleSync()
  onSyncDeviceIdChanged: if (syncConfigured()) scheduleSync()

  Component.onCompleted: if (syncConfigured()) scheduleSync()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  Timer {
    interval: root.barCycleIntervalSec * 1000
    running: root.barDisplayMode === "cycle" && root.enabledProviders.length > 1
    repeat: true
    onTriggered: root.activeIndex = (root.activeIndex + 1) % root.enabledProviders.length
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }

  Timer {
    id: syncDebounce
    interval: 1000
    repeat: false
    onTriggered: root.runSync()
  }

  Process {
    id: syncMkdirProcess
    running: false
    onRunningChanged: root.updateSyncRunning()
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (root.syncConfigured()) root.syncStatusText = "Usage sync mkdir failed"
        root.finishSyncRun()
        return
      }
      root.writeSyncSnapshot()
    }
  }

  Process {
    id: syncScanProcess
    running: false
    onRunningChanged: root.updateSyncRunning()
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.syncConfigured()) root.syncStatusText = "Usage sync scan failed"
      root.finishSyncRun()
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSyncScanOutput(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("model-usage/sync", text.trim())
    }
  }

  FileView {
    id: syncSnapshotFile
    path: root.syncSnapshotPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: hostnameFile
    path: "/etc/hostname"
    watchChanges: false
    printErrors: false
    onLoaded: root.detectedHostname = String(text() || "").trim()
  }

  onEnabledProvidersChanged: {
    if (enabledProviders.length === 0 || activeIndex >= enabledProviders.length) activeIndex = 0
  }

  function providerEnabled(id) {
    if (!settings || !settings.providers || !settings.providers[id]) return id === "claude" || id === "codex"
    return settings.providers[id].enabled !== false
  }

  function parseSyncEnabled(value) {
    if (value === true) return true
    var text = String(value || "").trim().toLowerCase()
    return text === "on" || text === "enabled" || text === "true" || text === "yes" || text === "1"
  }

  function syncConfigured() {
    return root.syncEnabled === true && String(root.syncDir || "").trim() !== ""
  }

  function syncSettingsChanged() {
    if (syncConfigured()) {
      scheduleSync()
    } else {
      syncDebounce.stop()
      syncRequestedWhileRunning = false
      aggregateData = ({})
      syncStatusText = ""
      syncRevision++
    }
  }

  function updateSyncRunning() {
    root.syncRunning = syncMkdirProcess.running || syncScanProcess.running
  }

  function scheduleSync() {
    if (!syncConfigured()) return
    syncDebounce.restart()
  }

  function runSync() {
    if (!syncConfigured()) return
    if (root.syncRunning) {
      syncRequestedWhileRunning = true
      return
    }

    syncRequestedWhileRunning = false
    syncStatusText = ""
    syncMkdirProcess.command = ["mkdir", "-p", root.syncEffectiveDir]
    syncMkdirProcess.running = true
  }

  function writeSyncSnapshot() {
    if (!syncConfigured()) {
      finishSyncRun()
      return
    }
    syncSnapshotFile.setText(JSON.stringify(localSnapshot(), null, 2) + "\n")
    Qt.callLater(root.startSyncScan)
  }

  function startSyncScan() {
    if (!syncConfigured()) {
      finishSyncRun()
      return
    }
    var script = "dir=$0; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; for f in \"$dir\"/*.json; do [[ -f \"$f\" ]] || continue; printf '===%s===\\n' \"$f\"; cat \"$f\"; printf '\\n=== EOM ===\\n'; done"
    syncScanProcess.command = ["bash", "-c", script, root.syncEffectiveDir]
    syncScanProcess.running = true
  }

  function finishSyncRun() {
    if (syncRequestedWhileRunning && syncConfigured()) {
      syncRequestedWhileRunning = false
      scheduleSync()
    }
  }

  function expandPath(path) {
    var value = String(path || "").trim()
    if (value === "") return ""
    if (value === "~") return home
    if (value.indexOf("~/") === 0) return home + value.substring(1)
    if (value.indexOf("$HOME/") === 0) return home + value.substring(5)
    if (value.charAt(0) !== "/") return home + "/" + value
    return value
  }

  function safeDeviceId(raw) {
    var value = String(raw || "").trim()
    if (value === "") value = Quickshell.env("HOSTNAME") || root.detectedHostname || Quickshell.env("HOST") || Quickshell.env("USER") || "device"
    value = value.replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^[._-]+|[._-]+$/g, "")
    if (value === "") value = "device"
    return value.length > 80 ? value.substring(0, 80) : value
  }

  function safeSnapshotFileName(rawFileName, rawDeviceId) {
    var value = String(rawFileName || "").trim()
    if (value === "") value = safeDeviceId(rawDeviceId) + ".json"
    value = value.split("/").pop().replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^[._-]+|[._-]+$/g, "")
    if (value === "") value = safeDeviceId(rawDeviceId) + ".json"
    if (!/\.json$/i.test(value)) value += ".json"
    return value.length > 100 ? value.substring(0, 95) + ".json" : value
  }

  function parseSyncScanOutput(output) {
    var lines = String(output || "").split("\n")
    var snapshots = []
    var currentPath = ""
    var currentJson = []

    function flush() {
      if (currentPath === "") return
      var raw = currentJson.join("\n").trim()
      try {
        var parsed = JSON.parse(raw)
        if (parsed && parsed.providers) snapshots.push(parsed)
      } catch (e) {
        console.warn("model-usage/sync", "Ignoring bad snapshot", currentPath, e)
      }
      currentPath = ""
      currentJson = []
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var start = line.match(/^===(.+)===$/)
      if (start && line !== "=== EOM ===") {
        flush()
        currentPath = start[1]
        currentJson = []
        continue
      }
      if (line === "=== EOM ===") {
        flush()
        continue
      }
      if (currentPath !== "") currentJson.push(line)
    }
    flush()

    aggregateData = aggregateSnapshots(snapshots)
    syncStatusText = ""
    syncRevision++
  }

  function cloneValue(value, fallback) {
    if (value === undefined || value === null) return fallback
    try {
      return JSON.parse(JSON.stringify(value))
    } catch (e) {
      return fallback
    }
  }

  function numberValue(value) {
    var n = Number(value || 0)
    return isFinite(n) ? Math.round(n) : 0
  }

  function dateString(date) {
    var y = date.getFullYear()
    var m = String(date.getMonth() + 1).padStart(2, "0")
    var d = String(date.getDate()).padStart(2, "0")
    return y + "-" + m + "-" + d
  }

  function recentDateStrings() {
    var result = []
    for (var offset = 6; offset >= 0; offset--) {
      var date = new Date()
      date.setDate(date.getDate() - offset)
      result.push(dateString(date))
    }
    return result
  }

  function emptyTokenBucket() {
    return { inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }
  }

  function addObjectNumbers(target, source) {
    if (!source) return
    for (var key in source) target[key] = numberValue(target[key]) + numberValue(source[key])
  }

  function aggregateSnapshots(snapshots) {
    var dates = recentDateStrings()
    var devices = {}
    var providers = {}

    function providerAcc(id) {
      if (providers[id]) return providers[id]
      var recentByDay = {}
      for (var d = 0; d < dates.length; d++) recentByDay[dates[d]] = 0
      providers[id] = {
        providerId: id,
        providerName: "",
        ready: false,
        hasLocalStats: false,
        todayPrompts: 0,
        todaySessions: 0,
        todayTotalTokens: 0,
        todayTokensByModel: ({}),
        recentByDay: recentByDay,
        totalPrompts: 0,
        totalSessions: 0,
        modelUsage: ({}),
        devices: ({})
      }
      return providers[id]
    }

    for (var i = 0; i < snapshots.length; i++) {
      var snapshot = snapshots[i]
      var device = safeDeviceId(snapshot.deviceId || "device")
      devices[device] = true
      var snapshotProviders = snapshot.providers || {}
      for (var providerId in snapshotProviders) {
        var stats = snapshotProviders[providerId] || {}
        var acc = providerAcc(String(providerId))
        acc.devices[device] = true
        if (stats.providerName && acc.providerName === "") acc.providerName = String(stats.providerName)
        acc.ready = acc.ready || stats.ready === true
        acc.hasLocalStats = acc.hasLocalStats || stats.hasLocalStats !== false
        acc.todayPrompts += numberValue(stats.todayPrompts)
        acc.todaySessions += numberValue(stats.todaySessions)
        acc.todayTotalTokens += numberValue(stats.todayTotalTokens)
        acc.totalPrompts += numberValue(stats.totalPrompts)
        acc.totalSessions += numberValue(stats.totalSessions)
        addObjectNumbers(acc.todayTokensByModel, stats.todayTokensByModel || {})

        var recent = Array.isArray(stats.recentDays) ? stats.recentDays : []
        for (var r = 0; r < recent.length; r++) {
          var day = recent[r] || {}
          var date = String(day.date || "")
          if (acc.recentByDay[date] !== undefined) acc.recentByDay[date] += numberValue(day.messageCount)
        }

        var usage = stats.modelUsage || {}
        for (var modelId in usage) {
          var bucket = acc.modelUsage[modelId]
          if (!bucket) bucket = acc.modelUsage[modelId] = emptyTokenBucket()
          var source = usage[modelId] || {}
          bucket.inputTokens += numberValue(source.inputTokens)
          bucket.outputTokens += numberValue(source.outputTokens)
          bucket.cacheReadInputTokens += numberValue(source.cacheReadInputTokens)
          bucket.cacheCreationInputTokens += numberValue(source.cacheCreationInputTokens)
        }
      }
    }

    var outProviders = {}
    for (var id in providers) {
      var acc = providers[id]
      var recentDays = []
      for (var di = 0; di < dates.length; di++) recentDays.push({ date: dates[di], messageCount: acc.recentByDay[dates[di]] || 0 })
      var providerDevices = Object.keys(acc.devices).sort()
      outProviders[id] = {
        providerId: acc.providerId,
        providerName: acc.providerName,
        ready: acc.ready || providerDevices.length > 0,
        hasLocalStats: acc.hasLocalStats,
        todayPrompts: acc.todayPrompts,
        todaySessions: acc.todaySessions,
        todayTotalTokens: acc.todayTotalTokens,
        todayTokensByModel: acc.todayTokensByModel,
        recentDays: recentDays,
        totalPrompts: acc.totalPrompts,
        totalSessions: acc.totalSessions,
        modelUsage: acc.modelUsage,
        deviceCount: providerDevices.length,
        devices: providerDevices
      }
    }

    return {
      schemaVersion: 1,
      updatedAt: new Date().toISOString(),
      updatedAtMs: Date.now(),
      deviceCount: Object.keys(devices).length,
      devices: Object.keys(devices).sort(),
      providers: outProviders
    }
  }

  function providerSnapshot(provider) {
    return {
      providerId: provider.providerId,
      providerName: provider.providerName,
      ready: provider.ready === true,
      hasLocalStats: provider.hasLocalStats !== false,
      todayPrompts: numberValue(provider.todayPrompts),
      todaySessions: numberValue(provider.todaySessions),
      todayTotalTokens: numberValue(provider.todayTotalTokens),
      todayTokensByModel: cloneValue(provider.todayTokensByModel, ({})),
      recentDays: cloneValue(provider.recentDays, []),
      totalPrompts: numberValue(provider.totalPrompts),
      totalSessions: numberValue(provider.totalSessions),
      modelUsage: cloneValue(provider.modelUsage, ({}))
    }
  }

  function localSnapshot() {
    var providerMap = {}
    for (var i = 0; i < providers.length; i++) {
      var provider = providers[i]
      if (provider.enabled) providerMap[provider.providerId] = providerSnapshot(provider)
    }
    return {
      schemaVersion: 1,
      deviceId: syncEffectiveDeviceId,
      updatedAt: new Date().toISOString(),
      providers: providerMap
    }
  }

  function syncedStatsFor(providerId) {
    var rev = syncRevision
    if (!syncConfigured() || !aggregateData || !aggregateData.providers) return null
    return aggregateData.providers[providerId] || null
  }

  function displayProvider(provider) {
    var stats = syncedStatsFor(provider.providerId)
    var synced = !!stats
    var deviceCount = synced ? Number(stats.deviceCount || aggregateData.deviceCount || 0) : 0

    return {
      providerId: provider.providerId,
      providerName: provider.providerName,
      providerIcon: provider.providerIcon,
      enabled: provider.enabled,
      ready: provider.ready || synced,
      refreshing: provider.refreshing || root.syncRunning,
      lastRefreshedAtMs: Math.max(provider.lastRefreshedAtMs || 0, root.aggregateUpdatedAtMs || 0),
      usageStatusText: provider.usageStatusText,
      authHelpText: provider.authHelpText,

      rateLimitPercent: provider.rateLimitPercent,
      rateLimitLabel: provider.rateLimitLabel,
      rateLimitResetAt: provider.rateLimitResetAt,
      secondaryRateLimitPercent: provider.secondaryRateLimitPercent,
      secondaryRateLimitLabel: provider.secondaryRateLimitLabel,
      secondaryRateLimitResetAt: provider.secondaryRateLimitResetAt,
      tierLabel: provider.tierLabel,

      todayPrompts: synced ? numberValue(stats.todayPrompts) : provider.todayPrompts,
      todaySessions: synced ? numberValue(stats.todaySessions) : provider.todaySessions,
      todayTotalTokens: synced ? numberValue(stats.todayTotalTokens) : provider.todayTotalTokens,
      todayTokensByModel: synced ? (stats.todayTokensByModel || ({})) : provider.todayTokensByModel,
      recentDays: synced ? (stats.recentDays || []) : provider.recentDays,
      totalPrompts: synced ? numberValue(stats.totalPrompts) : provider.totalPrompts,
      totalSessions: synced ? numberValue(stats.totalSessions) : provider.totalSessions,
      modelUsage: synced ? (stats.modelUsage || ({})) : provider.modelUsage,
      hasLocalStats: synced ? (stats.hasLocalStats !== false) : provider.hasLocalStats,

      syncEnabled: synced,
      syncDeviceCount: deviceCount,
      syncUpdatedAt: aggregateData && aggregateData.updatedAt ? aggregateData.updatedAt : "",

      formatResetTime: function(isoTimestamp) { return provider.formatResetTime(isoTimestamp) }
    }
  }

  function refresh() { refreshAll(true) }

  function refreshAll(force) {
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      if (p.enabled && typeof p.refresh === "function") p.refresh(force === true)
    }
    scheduleSync()
  }

  function formatTokenCount(n) {
    if (n === undefined || n === null) return "0"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  function friendlyModelName(id) {
    if (!id) return "Unknown"
    var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "")
    var parts = name.split("-")
    if (parts.length >= 3) return parts[0].charAt(0).toUpperCase() + parts[0].slice(1) + " " + parts[1] + "." + parts[2]
    if (parts.length === 2) return parts[0].charAt(0).toUpperCase() + parts[0].slice(1) + " " + parts[1]
    return name.charAt(0).toUpperCase() + name.slice(1)
  }
}
