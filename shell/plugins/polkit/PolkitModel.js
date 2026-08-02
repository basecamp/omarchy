function promptLooksFingerprint(text) {
  var s = String(text || "").toLowerCase()
  return s.indexOf("finger") !== -1 || s.indexOf("fprint") !== -1 || s.indexOf("swipe") !== -1
}

function promptLooksFido(text) {
  var s = String(text || "").toLowerCase()
  return s.indexOf("u2f") !== -1 || s.indexOf("fido") !== -1 ||
    s.indexOf("security key") !== -1
}

function promptLooksTouch(text) {
  return String(text || "").toLowerCase().indexOf("touch") !== -1
}

function fingerprintConfiguredFromPamConfig(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line || line.charAt(0) === "#") continue
    if (!line.match(/^auth\s+/)) continue
    if (line.indexOf("pam_fprintd.so") !== -1) return true
  }
  return false
}

function authenticationPresentation(method, fingerprintConfigured, laptopClosed) {
  var liveMethod = String(method || "waiting")
  var fingerprintLookahead = liveMethod === "waiting" && !!fingerprintConfigured && !laptopClosed
  return {
    method: liveMethod,
    glyph: fingerprintLookahead ? "fingerprint" : liveMethod,
    fingerprintLookahead: fingerprintLookahead
  }
}

function authenticationState(inputPrompt, supplementaryMessage, responseRequired) {
  var input = String(inputPrompt || "")
  var supplementary = String(supplementaryMessage || "")
  if (responseRequired) {
    return { method: "password", prompt: input || "Enter password" }
  }

  // PAM sends status cues in the supplementary message while it is waiting;
  // fall back to inputPrompt for modules that use it for those cues.
  var cue = supplementary || input
  if (promptLooksFido(cue)) return { method: "fido", prompt: cue || "Touch your security key" }
  if (promptLooksFingerprint(cue)) return { method: "fingerprint", prompt: cue || "Scan your fingerprint" }
  if (promptLooksTouch(cue)) return { method: "fido", prompt: cue || "Touch your security key" }
  return { method: "waiting", prompt: cue || "Authentication in progress..." }
}

function authorizationLabel(message) {
  var text = String(message || "")
  var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  return match ? "Authorize running '" + match[1] + "'" : text
}

if (typeof module !== "undefined") {
  module.exports = {
    promptLooksFingerprint: promptLooksFingerprint,
    promptLooksFido: promptLooksFido,
    fingerprintConfiguredFromPamConfig: fingerprintConfiguredFromPamConfig,
    authenticationPresentation: authenticationPresentation,
    authenticationState: authenticationState,
    authorizationLabel: authorizationLabel
  }
}
