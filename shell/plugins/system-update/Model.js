function emptyPackageState() {
  return {
    schemaVersion: 1,
    checked: "",
    checkedEpoch: 0,
    available: true,
    state: "loading",
    reason: "",
    count: 0,
    packages: []
  }
}

function emptyThemeState() {
  return {
    schemaVersion: 1,
    scanId: "",
    checked: "",
    checkedEpoch: 0,
    total: 0,
    reachable: 0,
    outdated: 0,
    actionable: 0,
    blocked: 0,
    review: 0,
    degraded: false,
    themes: []
  }
}

function parseJson(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    return JSON.parse(text)
  } catch (error) {
    return null
  }
}

function normalizeCount(value) {
  var number = parseInt(String(value === undefined ? 0 : value), 10)
  return isFinite(number) && number >= 0 ? number : 0
}

function parsePackageStatus(raw) {
  var data = parseJson(raw)
  var fallback = emptyPackageState()
  if (!data || data.schemaVersion !== 1 || !Array.isArray(data.packages)) {
    fallback.state = "invalid"
    fallback.reason = "invalid-helper-response"
    return fallback
  }

  var allowedStates = ["updates", "current", "unavailable", "invalid"]
  var state = String(data.state || "")
  if (allowedStates.indexOf(state) === -1) {
    fallback.state = "invalid"
    fallback.reason = "invalid-helper-state"
    return fallback
  }

  var packages = []
  for (var i = 0; i < data.packages.length; i++) {
    var row = data.packages[i] || {}
    var name = String(row.name || "")
    var installed = String(row.installed || "")
    var target = String(row.target || "")
    if (name === "" || installed === "" || target === "") {
      fallback.state = "invalid"
      fallback.reason = "invalid-package-row"
      return fallback
    }
    packages.push({ name: name, installed: installed, target: target })
  }

  var packageStateMatchesRows = (state === "updates" && packages.length > 0)
    || (state !== "updates" && packages.length === 0)
  var availabilityMatchesState = (state === "unavailable") === (data.available === false)
  if (!packageStateMatchesRows || !availabilityMatchesState) {
    fallback.state = "invalid"
    fallback.reason = "inconsistent-helper-response"
    return fallback
  }

  return {
    schemaVersion: 1,
    checked: String(data.checked || ""),
    checkedEpoch: normalizeCount(data.checkedEpoch),
    available: data.available !== false,
    state: state,
    reason: String(data.reason || ""),
    count: packages.length,
    packages: packages
  }
}

function parseThemeStatus(raw) {
  var data = parseJson(raw)
  var fallback = emptyThemeState()
  if (!data || data.schemaVersion !== 1 || !Array.isArray(data.themes)) {
    fallback.degraded = true
    return fallback
  }

  var allowedStates = [
    "clean", "update", "local-edits", "local-commits", "diverged",
    "unreachable", "no-upstream", "invalid"
  ]
  var themes = []
  for (var i = 0; i < data.themes.length; i++) {
    var row = data.themes[i] || {}
    var name = String(row.name || "")
    var state = String(row.state || "")
    if (name === "" || allowedStates.indexOf(state) === -1) {
      fallback.degraded = true
      return fallback
    }
    themes.push({
      name: name,
      state: state,
      current: row.current === true,
      behind: normalizeCount(row.behind),
      ahead: normalizeCount(row.ahead),
      reason: String(row.reason || ""),
      files: Array.isArray(row.files) ? row.files.slice(0, 5) : [],
      baseCommit: String(row.baseCommit || ""),
      targetCommit: String(row.targetCommit || "")
    })
  }

  var reachable = 0
  var outdated = 0
  var actionable = 0
  var blocked = 0
  var review = 0
  for (var j = 0; j < themes.length; j++) {
    var theme = themes[j]
    if (theme.state !== "unreachable" && theme.state !== "no-upstream" && theme.state !== "invalid") reachable++
    if (theme.behind > 0) outdated++
    if (theme.state === "update") actionable++
    if (theme.behind > 0 && theme.state !== "update") blocked++
    if (theme.state !== "clean" && theme.state !== "update") review++
  }

  return {
    schemaVersion: 1,
    scanId: String(data.scanId || ""),
    checked: String(data.checked || ""),
    checkedEpoch: normalizeCount(data.checkedEpoch),
    total: themes.length,
    reachable: reachable,
    outdated: outdated,
    actionable: actionable,
    blocked: blocked,
    review: review,
    degraded: data.degraded === true,
    themes: themes
  }
}

function themeStateLabel(theme) {
  if (!theme) return "Unknown"
  switch (theme.state) {
    case "update": return "Update available"
    case "clean": return "Up to date"
    case "local-edits": return "Local changes"
    case "local-commits": return "Local commits"
    case "diverged": return "Diverged"
    case "unreachable": return "Unavailable"
    case "no-upstream": return "No upstream"
    case "invalid": return "Invalid repository"
  }
  return "Unknown"
}

function themeStateDetail(theme) {
  if (!theme) return "Theme state is unavailable."
  if (theme.state === "update") return theme.behind + " reviewed commit" + (theme.behind === 1 ? "" : "s") + " ready to install."
  if (theme.state === "clean") return "The tracked remote branch is current."
  if (theme.reason === "tracked-edits") return "Tracked files have local edits. Commit or restore them before updating."
  if (theme.reason === "untracked-conflict") return "An incoming path would overwrite local untracked or ignored data."
  if (theme.reason === "local-commits") return "The local branch contains commits that are not on the tracked remote."
  if (theme.reason === "diverged-history") return "Local and remote history diverged; update manually and review the merge."
  if (theme.reason === "remote-unreachable" || theme.reason === "fetch-failed") return "The tracked remote could not be reached."
  if (theme.reason === "executable-git-filter") return "The repository defines executable Git filters and is not safe for automatic maintenance."
  if (theme.state === "no-upstream") return "The current branch has no usable tracked remote branch."
  if (theme.state === "invalid") return "The theme repository failed validation."
  return "Automatic update is blocked for this theme."
}

function checkedLabel(epoch) {
  var checked = Number(epoch || 0) * 1000
  if (!isFinite(checked) || checked <= 0) return "Not checked"
  var elapsed = Math.max(0, Date.now() - checked)
  var minutes = Math.floor(elapsed / 60000)
  if (minutes < 1) return "Checked just now"
  if (minutes < 60) return "Checked " + minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return "Checked " + hours + "h ago"
  return "Checked " + Math.floor(hours / 24) + "d ago"
}

function preferredTab(packageCount, themeCount, themeReview, themeDegraded, themeError) {
  if (normalizeCount(packageCount) > 0) return "packages"
  if (normalizeCount(themeCount) > 0
      || normalizeCount(themeReview) > 0
      || themeDegraded === true
      || String(themeError || "") !== "")
    return "themes"
  return "packages"
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyPackageState: emptyPackageState,
    emptyThemeState: emptyThemeState,
    parsePackageStatus: parsePackageStatus,
    parseThemeStatus: parseThemeStatus,
    themeStateLabel: themeStateLabel,
    themeStateDetail: themeStateDetail,
    checkedLabel: checkedLabel,
    preferredTab: preferredTab
  }
}
