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

function promptLabel(prompt) {
  // PAM decides what it is asking for, and it is not always a password. With
  // pam_u2f in the stack this prompt is the security key's PIN; a placeholder
  // that says "Enter password" invites the user to type their password into it,
  // where it is spent as a failed PIN attempt. A key allows eight before it
  // locks itself out for good, and recovery is a factory reset that destroys
  // every credential on it. Show what PAM actually asked for.
  var text = String(prompt || "").replace(/^\s+|\s+$/g, "")
  if (!text) return "Enter password"

  // PAM prompts carry their own punctuation ("Password: "), the dialog's own
  // label does not.
  text = text.replace(/\s*:\s*$/, "")
  if (!text) return "Enter password"

  // The several ways the stock modules phrase a password request all mean the
  // one thing the dialog already had a good label for.
  if (/^(unix )?password$/i.test(text) || /^enter password$/i.test(text)) return "Enter password"

  return text
}

function authorizationLabel(message) {
  var text = String(message || "")
  var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  return match ? "Authorize running '" + match[1] + "'" : text
}

if (typeof module !== "undefined") {
  module.exports = {
    promptLooksFingerprint: promptLooksFingerprint,
    promptLabel: promptLabel,
    fingerprintConfiguredFromPamConfig: fingerprintConfiguredFromPamConfig,
    authorizationLabel: authorizationLabel
  }
}
