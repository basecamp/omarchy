import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property string providerId: "claude"
    property string providerName: "Claude Code"
    property string providerIcon: "ai"
    property bool enabled: false
    property bool ready: false
    property bool refreshing: false
    property double lastRefreshedAtMs: 0
    property string usageStatusText: ""

    property real rateLimitPercent: -1
    property string rateLimitLabel: "Session (5-hour)"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: "Weekly (7-day)"
    property string secondaryRateLimitResetAt: ""

    property int todayPrompts: 0
    property int todaySessions: 0
    property int todayTotalTokens: 0
    property var todayTokensByModel: ({})

    property var recentDays: []
    property int totalPrompts: 0
    property int totalSessions: 0
    property var modelUsage: ({})
    property var dailyActivity: []

    property string tierLabel: ""
    property string authHelpText: "Run `claude auth login` to restore authoritative usage."
    property bool hasLocalStats: true
    property bool hasProjectStats: false

    property string oauthAccessToken: ""
    property double oauthExpiresAtMs: 0
    property string authMode: "none"
    property string subscriptionType: ""
    property string rateLimitTier: ""
    property bool hasAuthoritativeRateLimit: false

    property double lastProbeAtMs: 0
    property int probeMinIntervalMs: 15 * 60 * 1000
    property bool projectScanRerunForce: false

    property var providerSettings: ({})

    function resolvePath(p) {
        if (p && p.startsWith("~"))
            return (Quickshell.env("HOME") ?? "/home") + p.substring(1);
        return p;
    }

    function pathFromUrl(url) {
        const value = String(url || "");
        if (value.indexOf("file://") === 0)
            return decodeURIComponent(value.substring(7));
        return value;
    }

    readonly property string projectScannerScriptPath: pathFromUrl(Qt.resolvedUrl("../scripts/claude_usage_scanner.py"))

    FileView {
        id: statsFile
        path: root.resolvePath(root.providerSettings?.statsPath ?? "~/.claude/stats-cache.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseStats(text())
    }

    FileView {
        id: historyFile
        path: root.resolvePath("~/.claude/history.jsonl")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseHistory(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                console.error("model-usage/claude", "history.jsonl not found");
        }
    }

    FileView {
        id: credentialsFile
        path: root.resolvePath(root.providerSettings?.credentialsPath ?? "~/.claude/.credentials.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseCredentials(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                console.error("model-usage/claude", "credentials.json not found at", credentialsFile.path);
        }
    }

    Process {
        id: projectScanner
        running: false
        command: []

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyProjectUsageSummary(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (text.trim() !== "") console.warn("model-usage/claude", text.trim())
        }

        onExited: {
            root.finishRefresh();
            if (root.projectScanRerunForce) {
                root.projectScanRerunForce = false;
                root.startProjectScanner(true);
            }
        }
    }

    Timer {
        interval: root.probeMinIntervalMs
        running: root.enabled && root.oauthAccessToken !== ""
        repeat: true
        onTriggered: root.probeRateLimits(false)
    }

    function localDateString() {
        const now = new Date();
        const y = now.getFullYear();
        const m = String(now.getMonth() + 1).padStart(2, "0");
        const d = String(now.getDate()).padStart(2, "0");
        return y + "-" + m + "-" + d;
    }

    function parseStats(content) {
        try {
            const data = JSON.parse(content);
            const today = localDateString();

            const dailyModelTokens = data.dailyModelTokens ?? [];
            const todayTokenEntry = dailyModelTokens.find(d => d.date === today);
            root.todayTokensByModel = todayTokenEntry?.tokensByModel ?? {};

            let tokenSum = 0;
            const toks = root.todayTokensByModel;
            for (const k in toks)
                tokenSum += toks[k];
            root.todayTotalTokens = tokenSum;

            root.dailyActivity = data.dailyActivity ?? [];
            root.recentDays = root.dailyActivity.slice(-7);
            root.modelUsage = data.modelUsage ?? {};
            root.totalPrompts = data.totalMessages ?? 0;
            root.totalSessions = data.totalSessions ?? 0;
            root.ready = true;
        } catch (e) {
            console.error("model-usage/claude", "Failed to parse stats-cache.json:", e);
        }
    }

    function applyProjectUsageSummary(content) {
        try {
            const data = JSON.parse(String(content || "{}"));
            const prompts = Math.max(0, Number(data.totalPrompts || 0));
            if (prompts <= 0)
                return;

            root.hasProjectStats = true;
            root.todayPrompts = Math.max(0, Number(data.todayPrompts || 0));
            root.todaySessions = Math.max(0, Number(data.todaySessions || 0));
            root.todayTotalTokens = Math.max(0, Number(data.todayTotalTokens || 0));
            root.todayTokensByModel = data.todayTokensByModel || ({});
            root.recentDays = data.recentDays || [];
            root.modelUsage = data.modelUsage || ({});
            root.totalPrompts = prompts;
            root.totalSessions = Math.max(0, Number(data.totalSessions || 0));
            root.dailyActivity = data.dailyActivity || root.recentDays;
            root.ready = true;
        } catch (e) {
            console.error("model-usage/claude", "Failed to parse project usage summary:", e);
        }
    }

    function parseHistory(content) {
        if (root.hasProjectStats)
            return;
        try {
            const now = new Date();
            const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
            const lines = content.split("\n");
            let prompts = 0;
            const sessions = {};

            for (let i = lines.length - 1; i >= 0; i--) {
                const line = lines[i].trim();
                if (!line)
                    continue;
                try {
                    const entry = JSON.parse(line);
                    if ((entry.timestamp ?? 0) < startOfDay)
                        break;
                    prompts++;
                    if (entry.sessionId)
                        sessions[entry.sessionId] = true;
                } catch (e) {
                    continue;
                }
            }

            root.todayPrompts = prompts;
            root.todaySessions = Object.keys(sessions).length;
        } catch (e) {
            console.error("model-usage/claude", "Failed to parse history.jsonl:", e);
        }
    }

    function parseCredentials(content) {
        try {
            const data = JSON.parse(content);
            const oauth = data.claudeAiOauth ?? {};
            const fileAccessToken = oauth.accessToken ?? "";
            const fileExpiresAtMs = root.normalizeExpiresAtMs(oauth.expiresAt);
            const fileHasOAuth = fileAccessToken !== "";

            const tokenChanged = (root.oauthAccessToken !== fileAccessToken || root.oauthExpiresAtMs !== fileExpiresAtMs);
            root.oauthAccessToken = fileAccessToken;
            root.oauthExpiresAtMs = fileExpiresAtMs;
            if (tokenChanged)
                root.clearAuthoritativeRateLimits();

            root.authMode = fileHasOAuth ? "oauth" : "none";

            root.subscriptionType = oauth.subscriptionType ?? "";
            root.rateLimitTier = oauth.rateLimitTier ?? "";
            root.tierLabel = formatTier();

            if (root.oauthAccessToken && !root.oauthTokenExpired()) {
                if (root.usageStatusText === "Waiting for auth")
                    root.clearUsageStatus();
                root.probeRateLimits(false);
            } else if (!root.oauthAccessToken) {
                root.usageStatusText = "Waiting for auth";
                root.clearAuthoritativeRateLimits();
            } else {
                root.clearUsageStatus();
            }
        } catch (e) {
            console.error("model-usage/claude", "Failed to parse credentials.json:", e);
            root.usageStatusText = "Waiting for auth";
            root.clearAuthoritativeRateLimits();
        }
    }

    function formatTier() {
        if (!root.rateLimitTier)
            return root.subscriptionType || "";
        const match = root.rateLimitTier.match(/max_(\d+x)/i);
        if (match)
            return "Max " + match[1];
        if (root.subscriptionType)
            return root.subscriptionType.charAt(0).toUpperCase() + root.subscriptionType.slice(1);
        return "";
    }

    function normalizeExpiresAtMs(value) {
        const n = Number(value ?? 0);
        return (isFinite(n) && n > 0) ? n : 0;
    }

    function oauthTokenExpired() {
        if (!root.oauthAccessToken)
            return true;
        if (!root.oauthExpiresAtMs || !(root.oauthExpiresAtMs > 0))
            return false;
        return root.oauthExpiresAtMs <= Date.now();
    }

    function clearAuthoritativeRateLimits() {
        root.hasAuthoritativeRateLimit = false;
        root.rateLimitPercent = -1;
        root.rateLimitLabel = "Session (5-hour)";
        root.rateLimitResetAt = "";
        root.secondaryRateLimitPercent = -1;
        root.secondaryRateLimitLabel = "Weekly (7-day)";
        root.secondaryRateLimitResetAt = "";
    }

    function clearUsageStatus() {
        root.usageStatusText = "";
    }

    function parseNumber(value) {
        if (value === null || value === undefined)
            return NaN;
        return parseFloat(String(value).trim().replace("%", ""));
    }

    function utilizationPayloadUsesPercentScale(values) {
        for (let i = 0; i < values.length; i++) {
            const n = parseNumber(values[i]);
            if (n >= 1)
                return true;
        }
        return false;
    }

    function normalizeUtilization(value, percentScale) {
        const n = parseNumber(value);
        if (!(n >= 0))
            return -1;

        // Anthropic's OAuth usage endpoint currently reports percentages
        // (for example 37.0 or 1.0). Older clients/examples sometimes used
        // fractions (0.37). Treat a payload containing any value >= 1 as
        // percent-scaled so 1.0 renders as 1%, not 100%.
        if (percentScale === true || n > 1)
            return Math.min(1, n / 100);
        return Math.min(1, n);
    }

    function normalizeResetAt(value) {
        if (value === null || value === undefined)
            return "";
        const raw = String(value).trim();
        if (raw === "")
            return "";
        if (/^\d+$/.test(raw)) {
            let ts = parseInt(raw, 10);
            if (ts < 1e12)
                ts = ts * 1000;
            const d = new Date(ts);
            if (!isNaN(d.getTime()))
                return d.toISOString();
        }
        const parsed = new Date(raw);
        if (!isNaN(parsed.getTime()))
            return parsed.toISOString();
        return raw;
    }

    function oauthUsageBucket(payload, key) {
        const bucket = payload?.[key];
        if (bucket && typeof bucket === "object")
            return bucket;
        return null;
    }

    function applyAuthoritativeRateLimits(weekly, weeklyReset, session, sessionReset, sourceLabel) {
        const percentScale = root.utilizationPayloadUsesPercentScale([weekly, session]);
        const weeklyNorm = root.normalizeUtilization(weekly, percentScale);
        const sessionNorm = root.normalizeUtilization(session, percentScale);
        if (weeklyNorm < 0 && sessionNorm < 0)
            return false;

        root.hasAuthoritativeRateLimit = true;
        root.rateLimitPercent = -1;
        root.rateLimitLabel = "Session (5-hour)";
        root.rateLimitResetAt = "";
        root.secondaryRateLimitPercent = -1;
        root.secondaryRateLimitLabel = "Weekly (7-day)";
        root.secondaryRateLimitResetAt = "";

        if (sessionNorm >= 0)
            root.rateLimitPercent = sessionNorm;
        if (weeklyNorm >= 0)
            root.secondaryRateLimitPercent = weeklyNorm;
        if (sessionReset !== null && sessionReset !== undefined)
            root.rateLimitResetAt = root.normalizeResetAt(sessionReset);
        if (weeklyReset !== null && weeklyReset !== undefined)
            root.secondaryRateLimitResetAt = root.normalizeResetAt(weeklyReset);

        if (sourceLabel) {
            if (root.secondaryRateLimitPercent >= 0)
                root.secondaryRateLimitLabel = root.secondaryRateLimitLabel + " (" + sourceLabel + ")";
            else if (root.rateLimitPercent >= 0)
                root.rateLimitLabel = root.rateLimitLabel + " (" + sourceLabel + ")";
        }
        return true;
    }

    function finishRefresh() {
        root.refreshing = false;
        root.lastRefreshedAtMs = Date.now();
    }

    function probeOAuthUsage() {
        root.refreshing = true;
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + root.oauthAccessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const payload = JSON.parse(xhr.responseText ?? "{}");
                    const weeklyBucket = root.oauthUsageBucket(payload, "seven_day_oauth_apps") || root.oauthUsageBucket(payload, "seven_day");
                    const sessionBucket = root.oauthUsageBucket(payload, "five_hour");

                    if (root.applyAuthoritativeRateLimits(weeklyBucket?.utilization, weeklyBucket?.resets_at, sessionBucket?.utilization, sessionBucket?.resets_at, "")) {
                        root.clearUsageStatus();
                        root.finishRefresh();
                        return;
                    }
                } catch (e) {
                    console.error("model-usage/claude", "Failed to parse oauth usage response:", e);
                }
            }

            const body = xhr.responseText ? String(xhr.responseText).slice(0, 220) : "";
            const retryAfter = xhr.getResponseHeader("retry-after") || "";
            console.warn("model-usage/claude", "OAuth usage probe unavailable (status " + xhr.status + ")" + (body ? " body=" + body : ""));
            if (!root.hasAuthoritativeRateLimit) {
                root.usageStatusText = "Claude limits unavailable";
                root.authHelpText = xhr.status === 429
                    ? "Anthropic's usage endpoint is rate limiting checks right now" + (retryAfter ? " (retry after " + retryAfter + "s)" : "") + ". Local Claude Code stats are still shown."
                    : "Anthropic's usage endpoint returned status " + xhr.status + ". Local Claude Code stats are still shown.";
            }
            root.finishRefresh();
        };
        xhr.send();
    }

    function startProjectScanner(force) {
        if (projectScanner.running) {
            if (force === true)
                root.projectScanRerunForce = true;
            return false;
        }

        const command = ["python3", root.projectScannerScriptPath, root.resolvePath(root.providerSettings?.projectsPath ?? "~/.claude/projects")];
        if (force === true)
            command.push("--force");
        projectScanner.command = command;
        projectScanner.running = true;
        return true;
    }

    function refresh(force) {
        root.refreshing = true;
        statsFile.reload();
        historyFile.reload();
        credentialsFile.reload();
        root.startProjectScanner(force === true);

        if (root.oauthAccessToken && root.authMode === "oauth" && !root.oauthTokenExpired())
            root.probeRateLimits(force === true);
    }

    function formatResetTime(isoTimestamp) {
        if (!isoTimestamp)
            return "";
        const reset = new Date(isoTimestamp);
        const now = new Date();
        const diffMs = reset.getTime() - now.getTime();
        if (diffMs <= 0)
            return "now";
        const hours = Math.floor(diffMs / 3600000);
        const mins = Math.floor((diffMs % 3600000) / 60000);
        if (hours > 24)
            return Math.floor(hours / 24) + "d " + (hours % 24) + "h";
        if (hours > 0)
            return hours + "h " + mins + "m";
        return mins + "m";
    }

    function probeRateLimits(force) {
        if (!root.oauthAccessToken || root.authMode !== "oauth") {
            root.usageStatusText = "Waiting for auth";
            root.clearAuthoritativeRateLimits();
            root.finishRefresh();
            return;
        }

        if (root.oauthTokenExpired()) {
            root.clearUsageStatus();
            root.finishRefresh();
            return;
        }

        const nowMs = Date.now();
        if (force !== true && root.lastProbeAtMs > 0 && (nowMs - root.lastProbeAtMs) < root.probeMinIntervalMs) {
            root.finishRefresh();
            return;
        }
        root.lastProbeAtMs = nowMs;

        root.probeOAuthUsage();
    }
}
