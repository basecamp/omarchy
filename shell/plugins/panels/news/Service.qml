import QtQuick
import Quickshell
import Quickshell.Io
import "Collections.js" as Collections
import "ReadState.js" as ReadState

Item {
  id: root

  property var settings: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var items: []
  property var sources: []
  property var lastSeenBySource: ({})
  property var readIds: []
  property string fetchedAt: ""
  property string lastError: ""
  property string configurationError: ""
  property bool stale: false
  property bool partial: false
  property bool refreshing: false
  property bool refreshPending: false
  property bool refreshPendingPreferCache: true
  property int fetchMaxCacheAgeSec: 0
  property bool stateLoaded: false
  property var itemIndex: ({})

  readonly property string helperPath: (omarchyPath || "") + "/shell/plugins/panels/news/fetch_news.py"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string stateDir: stateRoot + "/omarchy/news"
  readonly property string statePath: stateDir + "/read.json"
  readonly property int refreshIntervalMin: intSetting("refreshIntervalMin", 15, 5, 120)
  readonly property int itemLimit: intSetting("itemLimit", 10, 5, 20)
  readonly property var techFeedIds: ["hacker-news", "ars-technica", "techcrunch", "the-verge", "wired", "phoronix", "its-foss", "openai-news", "hugging-face", "mit-ai"]
  readonly property var feedCatalog: [
    { "id": "hacker-news", "name": "Hacker News", "description": "Developer and startup news", "category": "developer", "url": "https://news.ycombinator.com/rss" },
    { "id": "ars-technica", "name": "Ars Technica", "description": "Deep technology, science and security", "category": "technology", "url": "https://feeds.arstechnica.com/arstechnica/index" },
    { "id": "techcrunch", "name": "TechCrunch", "description": "Startups, business and AI", "category": "startup", "url": "https://techcrunch.com/feed/" },
    { "id": "the-verge", "name": "The Verge", "description": "Mainstream technology and platforms", "category": "technology", "url": "https://www.theverge.com/rss/index.xml" },
    { "id": "wired", "name": "WIRED", "description": "Technology, science, security and culture", "category": "technology", "url": "https://www.wired.com/feed/rss" },
    { "id": "phoronix", "name": "Phoronix", "description": "Linux kernel, hardware and performance", "category": "linux", "url": "https://www.phoronix.com/rss.php" },
    { "id": "its-foss", "name": "It's FOSS", "description": "Accessible Linux and open-source coverage", "category": "linux", "url": "https://itsfoss.com/rss/" },
    { "id": "openai-news", "name": "OpenAI News", "description": "Official OpenAI product and research news", "category": "ai", "url": "https://openai.com/news/rss.xml" },
    { "id": "hugging-face", "name": "Hugging Face", "description": "Open models, tooling and AI research", "category": "ai", "url": "https://huggingface.co/blog/feed.xml" },
    { "id": "mit-ai", "name": "MIT News: AI", "description": "Academic AI research and developments", "category": "ai", "url": "https://news.mit.edu/rss/topic/artificial-intelligence2" }
  ]
  readonly property var enabledFeedIds: listSetting("enabledFeeds")
  readonly property var enabledSourceIds: ["omarchy"].concat(enabledFeedIds)
  readonly property string customFeeds: String(setting("customFeeds", "")).substring(0, 4096)
  readonly property var customFeedEntries: parseCustomFeedEntries(customFeeds)
  readonly property string collectionsSetting: String(setting("feedCollections", ""))
  readonly property var collections: Collections.parse(collectionsSetting)
  readonly property var selectableSources: buildSelectableSources()
  readonly property var collectionFilters: buildCollectionFilters()
  readonly property string sourceConfigSignature: enabledSourceIds.join(",") + "|" + customFeeds
  readonly property int unreadCount: countUnread()

  onSourceConfigSignatureChanged: if (stateLoaded) configurationRefreshTimer.restart()
  onCollectionsChanged: rebuildItemIndex()
  onItemLimitChanged: rebuildItemIndex()

  property string _stdout: ""
  property string _stderr: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function listSetting(name) {
    var value = setting(name, undefined)
    if (value === undefined) {
      return String(setting("feedPack", "")) === "Omarchy + Tech top 10" ? techFeedIds.slice() : []
    }
    if (!value || typeof value.length !== "number" || typeof value === "string") return []
    var result = []
    for (var i = 0; i < value.length; i++) {
      var sourceId = String(value[i] || "")
      if (techFeedIds.indexOf(sourceId) !== -1 && result.indexOf(sourceId) === -1) result.push(sourceId)
    }
    return result
  }

  function parseCustomFeedEntries(value) {
    var result = []
    var parts = String(value || "").replace(/\n/g, ";").split(";")
    for (var i = 0; i < parts.length; i++) {
      var raw = String(parts[i] || "").trim()
      if (raw === "") continue
      var separator = raw.indexOf("|")
      var name = separator >= 0 ? raw.substring(0, separator).trim() : ""
      var url = separator >= 0 ? raw.substring(separator + 1).trim() : raw
      result.push({ "name": name, "url": url })
    }
    return result
  }

  function buildSelectableSources() {
    var result = [{
      "id": "omarchy",
      "name": "Omarchy",
      "category": "official",
      "url": "https://omarchy.org/news/rss.xml"
    }]
    for (var i = 0; i < feedCatalog.length; i++) {
      if (enabledFeedIds.indexOf(String(feedCatalog[i].id || "")) >= 0) result.push(feedCatalog[i])
    }
    for (var customIndex = 0; customIndex < customFeedEntries.length; customIndex++) {
      var entry = customFeedEntries[customIndex]
      var name = String(entry.name || "").trim()
      var url = String(entry.url || "").trim()
      if (name === "") name = url.replace(/^https:\/\//, "").split("/")[0]
      result.push({ "id": "custom-url-" + customIndex, "name": name, "category": "custom", "url": url })
    }
    return result
  }

  function buildCollectionFilters() {
    var result = []
    for (var i = 0; i < collections.length; i++) {
      var key = "collection:" + String(collections[i].id || "")
      result.push({
        "id": key,
        "name": String(collections[i].name || "Collection"),
        "category": "collection",
        "itemCount": (itemIndex[key] || []).length
      })
    }
    return result
  }

  function countUnread() {
    if (!stateLoaded || items.length === 0) return 0
    var total = 0
    for (var i = 0; i < items.length; i++)
      if (!ReadState.isRead(items[i], items, readIds, lastSeenBySource)) total++
    return total
  }

  function rebuildItemIndex() {
    itemIndex = Collections.buildItemIndex(items, collections, itemLimit)
  }

  function itemsForSource(sourceId) {
    var key = String(sourceId || "all")
    return itemIndex[key] || []
  }

  function refresh(preferCache) {
    if (fetchProcess.running) {
      refreshPending = true
      refreshPendingPreferCache = refreshPendingPreferCache && preferCache === true
      return
    }
    if (helperPath === "/shell/plugins/panels/news/fetch_news.py") return
    _stdout = ""
    _stderr = ""
    fetchMaxCacheAgeSec = preferCache === true ? refreshIntervalMin * 60 : 0
    refreshing = true
    fetchProcess.running = true
  }

  function applyResult(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!parsed || parsed.ok !== true || !Array.isArray(parsed.items)) throw new Error("invalid result")
      items = parsed.items
      rebuildItemIndex()
      sources = Array.isArray(parsed.sources) ? parsed.sources : []
      fetchedAt = String(parsed.fetchedAt || "")
      stale = parsed.stale === true
      partial = parsed.partial === true
      configurationError = String(parsed.configurationError || "")
      lastError = String(parsed.error || "")
    } catch (error) {
      lastError = "Could not read the RSS feed"
    }
  }

  function markArticleSeen(article) {
    if (!stateLoaded || !article) return
    var next = ReadState.mark(readIds, article.id)
    if (next === readIds) return
    readIds = next
    readState.setText(JSON.stringify({ version: 3, readIds: next, lastSeenBySource: lastSeenBySource }, null, 2) + "\n")
  }

  function loadReadState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      readIds = Array.isArray(parsed.readIds) ? parsed.readIds.filter(function(id) { return typeof id === "string" }).slice(-4096) : []
      if (parsed.lastSeenBySource && typeof parsed.lastSeenBySource === "object") {
        lastSeenBySource = parsed.lastSeenBySource
      } else if (parsed.lastSeenId) {
        var legacyId = String(parsed.lastSeenId)
        lastSeenBySource = ({ "omarchy": legacyId.indexOf("omarchy:") === 0 ? legacyId : "omarchy:" + legacyId })
      } else {
        lastSeenBySource = ({})
      }
    } catch (error) {
      lastSeenBySource = ({})
    }
    stateLoaded = true
  }

  function shortError(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 180 ? value.substring(0, 177) + "…" : value
  }

  FileView {
    id: readState
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadReadState(text())
    onLoadFailed: root.stateLoaded = true
  }

  Process {
    id: prepareState
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: function() {
      readState.reload()
      root.refresh()
    }
  }

  Process {
    id: fetchProcess
    command: ["python3", root.helperPath, "--stream", "--sources", root.enabledSourceIds.join(","), "--custom-feeds", root.customFeeds, "--max-cache-age", String(root.fetchMaxCacheAgeSec), "--item-limit", String(root.itemLimit)]
    running: false
    stdout: SplitParser {
      onRead: function(data) {
        if (String(data).trim() !== "") root.applyResult(data)
      }
    }
    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
    onExited: function(exitCode) {
      root.refreshing = false
      var error = String(fetchStderr.text || root._stderr || "")
      if (exitCode !== 0) root.lastError = root.shortError(error || "Could not fetch RSS feeds")
      if (root.refreshPending) {
        var preferCache = root.refreshPendingPreferCache
        root.refreshPending = false
        root.refreshPendingPreferCache = true
        Qt.callLater(function() { root.refresh(preferCache) })
      }
    }
  }

  Timer {
    id: configurationRefreshTimer
    interval: 250
    repeat: false
    onTriggered: root.refresh(true)
  }

  Timer {
    interval: root.refreshIntervalMin * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
}
