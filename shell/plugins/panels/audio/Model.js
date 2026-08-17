function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function isAudioSource(node) {
  if (!node) return false
  if (node.audio) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Audio/Source") !== -1
    || mediaClass.indexOf("AudioSource") !== -1
    || mediaClass.indexOf("Source") !== -1
}

function listSnapshot(list) {
  return list && list.slice ? list.slice() : []
}

function outputVolumeName(volume, muted) {
  if (muted) return "Muted"
  var p = Math.round(volume * 100)
  if (p === 0) return "Silenced"
  if (p >= 100) return "Concert hall"
  if (p >= 85) return "Party mode"
  if (p >= 70) return "Cranked up"
  if (p >= 50) return "Steady groove"
  if (p >= 30) return "Easy listening"
  if (p >= 15) return "Murmur"
  return "Whisper"
}

function parseSinkAvailability(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length >= 2) next[parts[0]] = parts[1] !== "0"
  }
  return next
}

function parseOutputTargets(raw) {
  var parsed
  try {
    parsed = JSON.parse(String(raw || ""))
  } catch (_) {
    return null
  }
  if (!Array.isArray(parsed)) return null

  var targets = []
  var seen = {}
  for (var i = 0; i < parsed.length; i++) {
    var item = parsed[i]
    if (!item || typeof item !== "object") continue

    var sinkName = String(item.sinkName || "").trim()
    var portName = String(item.portName || "").trim()
    if (!sinkName) continue

    var key = sinkName + "|" + portName
    if (seen[key]) continue
    seen[key] = true
    targets.push({
      sinkName: sinkName,
      portName: portName,
      portDescription: String(item.portDescription || "").trim(),
      sinkDescription: String(item.sinkDescription || sinkName).trim(),
      kind: String(item.kind || "speaker"),
      active: item.active === true
    })
  }
  if (parsed.length > 0 && targets.length === 0) return null
  return targets
}

function outputTargetLabel(target, targetCountForSink) {
  if (!target) return "Unknown"
  var portLabel = friendlyDeviceLabel(target.portDescription)
  var sinkLabel = friendlyDeviceLabel(target.sinkDescription)
  if (targetCountForSink > 1 && portLabel) return portLabel
  if (target.kind === "headphones" && portLabel) return portLabel
  return sinkLabel || portLabel || target.sinkName || "Unknown"
}

function joinOutputTargets(targets, sinks) {
  var values = Array.isArray(targets) ? targets : []
  var nodes = Array.isArray(sinks) ? sinks : []
  var counts = {}
  var joined = []

  for (var i = 0; i < values.length; i++)
    counts[values[i].sinkName] = (counts[values[i].sinkName] || 0) + 1

  for (var j = 0; j < values.length; j++) {
    var target = values[j]
    var node = null
    for (var k = 0; k < nodes.length; k++) {
      if (nodes[k] && String(nodes[k].name || "") === target.sinkName) {
        node = nodes[k]
        break
      }
    }
    if (!node) continue

    joined.push({
      sinkName: target.sinkName,
      portName: target.portName,
      label: outputTargetLabel(target, counts[target.sinkName]),
      description: target.sinkDescription,
      kind: target.kind,
      active: target.active,
      node: node
    })
  }
  return joined
}

function fallbackOutputTargets(sinks, defaultSink) {
  var nodes = Array.isArray(sinks) ? sinks : []
  var targets = []
  for (var i = 0; i < nodes.length; i++) {
    var node = nodes[i]
    if (!node) continue
    targets.push({
      sinkName: String(node.name || ""),
      portName: "",
      label: nodeLabel(node),
      description: nodeLabel(node),
      kind: isHeadphones(node) ? "headphones" : "speaker",
      active: !!defaultSink && (node === defaultSink || node.id === defaultSink.id),
      node: node
    })
  }
  return targets
}

function outputTargetGlyph(target) {
  var kind = String(target && target.kind || "")
  if (kind === "headphones") return "󰋋"
  if (kind === "bluetooth") return "󰂯"
  if (kind === "display") return "󰍹"
  return "󰓃"
}

function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Output$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\bMicrophones\b/g, "Microphone")
  return label
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function nodeLabel(node) {
  if (!node) return "Unknown"
  var p = nodeProps(node)
  var nickname = friendlyDeviceLabel(node.nickname || node.nick || p["node.nick"] || p["device.profile.description"] || "")
  if (nickname) return nickname
  return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
}

function isHeadphones(node) {
  if (!node) return false
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || "",
    p["node.description"] || "",
    p["node.nick"] || ""
  ].join(" ")).toLowerCase()
  return blob.indexOf("headphone") !== -1
    || blob.indexOf("headset") !== -1
    || blob.indexOf("earbud") !== -1
    || blob.indexOf("earphone") !== -1
    || blob.indexOf("airpod") !== -1
}

function sinkGlyph(node) {
  if (!node) return "󰓃"
  if (isHeadphones(node)) return "󰋋"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

function sourceGlyph(node) {
  if (!node) return "󰍬"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("headset") !== -1) return "󰋋"
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
  return "󰍬"
}

function friendlyStreamLabel(label) {
  label = String(label || "").trim()
  if (!label) return ""

  var known = {
    "spotify": "Spotify"
  }
  var normalized = label.toLowerCase()
  return known[normalized] || label
}

function streamLabelKey(label) {
  return String(label || "").trim().toLowerCase()
}

function streamLabelIsGeneric(label) {
  return streamLabelKey(label) === "audio-src"
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function mprisPlayerLabel(player) {
  if (!player) return ""
  return friendlyStreamLabel(player.identity || player.desktopEntry || "")
}

function mprisPlayerIsProxy(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
  var streamKey = streamLabelKey(friendlyStreamLabel(streamLabel))
  var playerKey = streamLabelKey(playerLabel)
  if (!streamKey || !playerKey) return false
  return streamKey === playerKey
    || streamKey.indexOf(playerKey) !== -1
    || playerKey.indexOf(streamKey) !== -1
}

function mprisLabelsFor(players, predicate) {
  var values = Array.isArray(players) ? players : []
  var playingCandidates = []
  var candidates = []
  var playingProxyCandidates = []
  var proxyCandidates = []

  for (var i = 0; i < values.length; i++) {
    var player = values[i]
    if (!player) continue
    if (!player.isPlaying && !player.canPlay) continue

    var playerLabel = mprisPlayerLabel(player)
    if (!playerLabel || !predicate(playerLabel)) continue

    if (mprisPlayerIsProxy(player)) {
      if (player.isPlaying) playingProxyCandidates.push(playerLabel)
      proxyCandidates.push(playerLabel)
    } else {
      if (player.isPlaying) playingCandidates.push(playerLabel)
      candidates.push(playerLabel)
    }
  }

  if (playingCandidates.length === 1) return playingCandidates[0]
  if (playingCandidates.length === 0 && playingProxyCandidates.length === 1) return playingProxyCandidates[0]
  if (candidates.length === 1) return candidates[0]
  if (candidates.length === 0 && proxyCandidates.length === 1) return proxyCandidates[0]
  return ""
}

function matchingMprisStreamLabel(label, players) {
  if (streamLabelIsGeneric(label)) return ""
  return mprisLabelsFor(players, function(playerLabel) {
    return streamRepresentsMprisPlayer(label, playerLabel)
  })
}

function unmatchedMprisStreamLabel(label, players, streams) {
  if (!streamLabelIsGeneric(label)) return ""

  return mprisLabelsFor(players, function(playerLabel) {
    var values = Array.isArray(streams) ? streams : []
    for (var i = 0; i < values.length; i++) {
      var stream = values[i]
      var streamLabel = rawStreamLabel(stream)
      if (!streamLabelIsGeneric(streamLabel) && streamRepresentsMprisPlayer(streamLabel, playerLabel))
        return false
    }
    return true
  })
}

function streamLabel(node, players, streams) {
  if (!node) return "Stream"
  var label = rawStreamLabel(node)
  return friendlyStreamLabel(matchingMprisStreamLabel(label, players)
    || unmatchedMprisStreamLabel(label, players, streams)
    || label) || "Stream"
}

function streamRepresentsPlayer(node, player, players, streams) {
  if (!node || !player) return false
  var playerLabel = mprisPlayerLabel(player)
  if (!playerLabel) return false

  var label = rawStreamLabel(node)
  if (!streamLabelIsGeneric(label)) return streamRepresentsMprisPlayer(label, playerLabel)
  return streamRepresentsMprisPlayer(streamLabel(node, players, streams), playerLabel)
}

if (typeof module !== "undefined") {
  module.exports = {
    isPlaybackStream: isPlaybackStream,
    isAudioSource: isAudioSource,
    listSnapshot: listSnapshot,
    outputVolumeName: outputVolumeName,
    parseSinkAvailability: parseSinkAvailability,
    parseOutputTargets: parseOutputTargets,
    outputTargetLabel: outputTargetLabel,
    joinOutputTargets: joinOutputTargets,
    fallbackOutputTargets: fallbackOutputTargets,
    outputTargetGlyph: outputTargetGlyph,
    friendlyDeviceLabel: friendlyDeviceLabel,
    nodeProps: nodeProps,
    nodeLabel: nodeLabel,
    isHeadphones: isHeadphones,
    sinkGlyph: sinkGlyph,
    sourceGlyph: sourceGlyph,
    friendlyStreamLabel: friendlyStreamLabel,
    streamLabelKey: streamLabelKey,
    streamLabelIsGeneric: streamLabelIsGeneric,
    rawStreamLabel: rawStreamLabel,
    mprisPlayerLabel: mprisPlayerLabel,
    mprisPlayerIsProxy: mprisPlayerIsProxy,
    streamRepresentsMprisPlayer: streamRepresentsMprisPlayer,
    mprisLabelsFor: mprisLabelsFor,
    matchingMprisStreamLabel: matchingMprisStreamLabel,
    unmatchedMprisStreamLabel: unmatchedMprisStreamLabel,
    streamLabel: streamLabel,
    streamRepresentsPlayer: streamRepresentsPlayer
  }
}
