import QtQuick
import Quickshell
import "providers"

Item {
    id: root
    visible: false

    property var settings: ({})

    Opencode {
        id: opencodeProvider
        enabled: true
        providerSettings: root.settings?.providers?.opencode ?? ({})
    }

    property var providers: [opencodeProvider]
    property var enabledProviders: {
        var result = []
        if (opencodeProvider.enabled) result.push(displayProvider(opencodeProvider))
        return result
    }

    property bool refreshing: opencodeProvider.refreshing
    property double lastRefreshedAtMs: opencodeProvider.lastRefreshedAtMs || 0
    property int refreshIntervalSec: Math.max(30, Number(root.setting("refreshIntervalSec", 300)))

    Timer {
        interval: root.refreshIntervalSec * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshAll()
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined
        return value === undefined || value === null ? fallback : value
    }

    function displayProvider(provider) {
        return {
            providerId: provider.providerId,
            providerName: provider.providerName,
            providerIcon: provider.providerIcon,
            enabled: provider.enabled,
            ready: provider.ready,
            refreshing: provider.refreshing,
            lastRefreshedAtMs: provider.lastRefreshedAtMs,
            usageStatusText: provider.usageStatusText,
            authHelpText: provider.authHelpText,
            todayPrompts: provider.todayPrompts,
            todaySessions: provider.todaySessions,
            todayTotalTokens: provider.todayTotalTokens,
            todayTokensByModel: provider.todayTokensByModel,
            recentDays: provider.recentDays,
            totalPrompts: provider.totalPrompts,
            totalSessions: provider.totalSessions,
            modelUsage: provider.modelUsage,
            hasLocalStats: provider.hasLocalStats,
            formatResetTime: function(isoTimestamp) { return provider.formatResetTime(isoTimestamp) }
        }
    }

    function refreshAll(force) {
        opencodeProvider.refresh(force === true)
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
        // Handle JSON string model ids like {"id":"deepseek","providerID":"opencode"}
        if (id.charAt(0) === "{") {
            try {
                var parsed = JSON.parse(id)
                var modelId = String(parsed.id || "")
                var provider = String(parsed.providerID || "")
                if (modelId && provider) return modelId + " (" + provider + ")"
                if (modelId) return modelId
            } catch (e) {}
        }
        return String(id)
    }
}
