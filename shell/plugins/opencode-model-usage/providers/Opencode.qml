import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property string providerId: "opencode"
    property string providerName: "OpenCode"
    property string providerIcon: "code"
    property bool enabled: false
    property bool ready: false
    property bool refreshing: false
    property double lastRefreshedAtMs: 0
    property string usageStatusText: ""
    property string authHelpText: ""

    property int todayPrompts: 0
    property int todaySessions: 0
    property int todayTotalTokens: 0
    property var todayTokensByModel: ({})

    property var recentDays: []
    property int totalPrompts: 0
    property int totalSessions: 0
    property var modelUsage: ({})
    property var dailyActivity: []

    property bool hasLocalStats: true
    property var providerSettings: ({})

    property string dbPath: "~/.local/share/opencode/opencode.db"

    readonly property string scannerScriptPath: pathFromUrl(Qt.resolvedUrl("../scripts/opencode_usage_scanner.py"))

    function pathFromUrl(url) {
        var value = String(url || "")
        if (value.indexOf("file://") === 0)
            return decodeURIComponent(value.substring(7))
        return value
    }

    function resolvePath(p) {
        if (p && p.startsWith("~"))
            return (Quickshell.env("HOME") ?? "/home") + p.substring(1)
        return p
    }

    FileView {
        id: dbFile
        path: root.resolvePath(root.dbPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.refresh(false)
        onLoadFailed: function(error) {
            root.usageStatusText = "OpenCode DB not found"
            root.authHelpText = "Start an opencode session to create " + root.dbPath
        }
    }

    Process {
        id: scanner
        running: false
        command: []

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyUsage(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: function(text) {
                if (text && text.trim() !== "")
                    console.warn("model-usage/opencode", text.trim())
            }
        }

        onExited: {
            root.refreshing = false
            root.lastRefreshedAtMs = Date.now()
        }
    }

    function applyUsage(content) {
        try {
            var data = JSON.parse(String(content || "{}"))
            if (!data.ready)
                return

            root.ready = true
            root.hasLocalStats = data.hasLocalStats !== false
            root.todayPrompts = Math.max(0, Number(data.todayPrompts || 0))
            root.todaySessions = Math.max(0, Number(data.todaySessions || 0))
            root.todayTotalTokens = Math.max(0, Number(data.todayTotalTokens || 0))
            root.todayTokensByModel = data.todayTokensByModel || ({})
            root.recentDays = data.recentDays || []
            root.modelUsage = data.modelUsage || ({})
            root.totalPrompts = Math.max(0, Number(data.totalPrompts || 0))
            root.totalSessions = Math.max(0, Number(data.totalSessions || 0))
            root.dailyActivity = data.recentDays || []
        } catch (e) {
            root.usageStatusText = "Scanner error"
            root.authHelpText = String(e)
            console.error("model-usage/opencode", "Failed to parse scanner output:", e)
        }
    }

    function refresh(force) {
        if (scanner.running)
            return

        root.refreshing = true
        scanner.command = ["python3", root.scannerScriptPath, root.resolvePath(root.dbPath)]
        scanner.running = true
    }

    function formatResetTime(isoTimestamp) {
        return ""
    }
}
