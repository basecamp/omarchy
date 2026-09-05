function promptLooksFingerprint(text) {
  var s = String(text || "").toLowerCase()
  return s.indexOf("finger") !== -1 || s.indexOf("fprint") !== -1 || s.indexOf("swipe") !== -1
}

function fingerprintConfiguredFromPamConfig(raw) {
  // Fingerprint is available whenever pam_fprintd appears anywhere in the auth
  // stack — it need not be the first module. A clamshell gate (pam_exec) may
  // legitimately precede it to skip fingerprint while the lid is closed.
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line || line.charAt(0) === "#") continue
    if (!line.match(/^auth\s+/)) continue
    if (line.indexOf("pam_fprintd.so") !== -1) return true
  }
  return false
}

function displayNameForAgent(slug) {
  switch (String(slug || "").trim()) {
    case "pi": return "Pi"
    case "omp": return "Oh My Pi"
    case "opencode": return "OpenCode"
    case "ori": return "Ori"
    case "claude": return "Claude Code"
    case "codex": return "Codex"
    case "crush": return "Crush"
    case "grok": return "Grok"
    case "agy": return "Antigravity"
    case "copilot": return "GitHub Copilot"
    default: return ""
  }
}

function authorizationLabel(message, agentDisplayName) {
  var text = String(message || "")
  var agent = String(agentDisplayName || "").trim()
  var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  if (match) {
    return agent
      ? agent + " wants: '" + match[1] + "'"
      : "Authorize running '" + match[1] + "'"
  }
  return text
}

if (typeof module !== "undefined") {
  module.exports = {
    promptLooksFingerprint: promptLooksFingerprint,
    fingerprintConfiguredFromPamConfig: fingerprintConfiguredFromPamConfig,
    displayNameForAgent: displayNameForAgent,
    authorizationLabel: authorizationLabel
  }
}
