function authCapabilitiesFromPamConfig(raw) {
  var lines = String(raw || "").split("\n")
  var capabilities = { fingerprint: false, fido: false, methods: [] }
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line || line.charAt(0) === "#") continue
    if (!line.match(/^auth\s+/)) continue
    if (line.indexOf("pam_fprintd.so") !== -1) {
      capabilities.fingerprint = true
      if (capabilities.methods.indexOf("fingerprint") === -1) capabilities.methods.push("fingerprint")
    }
    if (line.indexOf("pam_u2f.so") !== -1) {
      capabilities.fido = true
      if (capabilities.methods.indexOf("fido") === -1) capabilities.methods.push("fido")
    }
  }
  return capabilities
}

function fingerprintConfiguredFromPamConfig(raw) {
  return authCapabilitiesFromPamConfig(raw).fingerprint
}

function authenticationState(inputPrompt, supplementaryMessage, responseRequired) {
  var input = String(inputPrompt || "")
  var supplementary = String(supplementaryMessage || "")
  if (responseRequired) {
    return { method: "password", prompt: input || "Enter password" }
  }

  // PAM sends noninteractive status cues in the supplementary message; fall
  // back to inputPrompt for modules that use it instead.
  var cue = supplementary || input
  if (cue) return { method: "physical", prompt: cue }
  return { method: "waiting", prompt: "Authentication in progress..." }
}

function authorizationLabel(message) {
  var text = String(message || "")
  var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  return match ? "Authorize running '" + match[1] + "'" : text
}

if (typeof module !== "undefined") {
  module.exports = {
    authCapabilitiesFromPamConfig: authCapabilitiesFromPamConfig,
    fingerprintConfiguredFromPamConfig: fingerprintConfiguredFromPamConfig,
    authenticationState: authenticationState,
    authorizationLabel: authorizationLabel
  }
}
