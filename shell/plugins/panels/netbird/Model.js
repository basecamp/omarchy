// NetBird status JSON is shaped differently from Tailscale, but the widget
// needs the same shape: a self identity, a list of peers, and a connection
// state.  This module bridges the two without depending on QML so it stays
// unit-testable from Node.

function parseNetbirdIp(raw) {
  // NetBird writes the CIDR suffix on self but not on peers, so strip it.
  return String(raw || "").replace(/\/\d+$/, "")
}

function shortName(fqdn) {
  var value = String(fqdn || "")
  // NetBird FQDNs end in .netbird.cloud; strip that and keep the short label.
  if (value.length > 0 && value.charAt(value.length - 1) === ".") {
    value = value.slice(0, -1)
  }
  var dot = value.indexOf(".")
  return dot === -1 ? value : value.substring(0, dot)
}

function osIcon(os) {
  // NetBird does not expose peer OS in status JSON, so guess from FQDN.
  var value = String(os || "").toLowerCase()
  if (value === "linux") return "󰌽"
  if (value === "macos" || value === "ios" || value.indexOf("mac") === 0 || value.indexOf("iphone") === 0) return "󰀵"
  if (value === "windows" || value.indexOf("win") === 0) return "󰍲"
  if (value === "android") return "󰀲"
  return "󰟀"
}

function peerFromDetail(detail) {
  var fqdn = String(detail.fqdn || "")
  var ip = parseNetbirdIp(detail.netbirdIp || "")
  var status = String(detail.status || "Idle")

  return {
    id: fqdn,
    HostName: shortName(fqdn),
    DNSName: fqdn,
    DisplayName: shortName(fqdn),
    NetbirdIP: ip,
    Online: status === "Connected" || status === "Connecting",
    Status: status,
    ConnectionType: String(detail.connectionType || "-"),
    Latency: Number(detail.latency || 0),
    Networks: detail.networks || []
  }
}

function parseProfiles(raw) {
  // `netbird profile list` prints plain text, not JSON. The lines look like:
  //   Found 2 profiles:
  //   ✓ default
  //     work
  // The checkmark marks the selected profile.
  var lines = String(raw || "").split(/\r?\n/)
  var profiles = []
  var selected = ""

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    // Skip the summary line (e.g. "Found 2 profiles:").
    if (/^Found\s+\d+\s+profiles:$/i.test(line.trim())) continue
    // Profile lines are indented with an optional checkmark for the selected one.
    var match = line.match(/^([✓✗])?\s*(.+)$/)
    if (!match) continue
    var mark = match[1] || ""
    var name = match[2].trim()
    if (!name) continue
    var selectedProfile = mark === "✓"
    profiles.push({ id: name, name: name, selected: selectedProfile })
    if (selectedProfile) selected = name
  }

  return {
    profiles: profiles,
    selectedProfileId: selected,
    selectedProfileLabel: selected
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Disconnected" }

  try {
    var data = JSON.parse(text)
    var daemonStatus = String(data.daemonStatus || "Unknown")
    var selfFqdn = String(data.fqdn || "")
    var selfIp = parseNetbirdIp(data.netbirdIp || "")
    var profileName = String(data.profileName || "")
    var managementConnected = data.management && data.management.connected === true

    var rawPeers = (data.peers && data.peers.details) || []
    var peers = []
    for (var i = 0; i < rawPeers.length; i++) {
      var peer = peerFromDetail(rawPeers[i])
      // Show all peers (online and idle) — NetBird lists them all.
      peers.push(peer)
    }

    // Sort: Connected first, then Connecting, then Idle, alphabetically within each.
    peers.sort(function(a, b) {
      var order = { "Connected": 0, "Connecting": 1, "Idle": 2 }
      var aOrder = order[a.Status] !== undefined ? order[a.Status] : 3
      var bOrder = order[b.Status] !== undefined ? order[b.Status] : 3
      if (aOrder !== bOrder) return aOrder - bOrder
      return String(a.HostName).localeCompare(String(b.HostName))
    })

    var running = daemonStatus === "Connected"
    var needsLogin = daemonStatus === "NeedsLogin" || (!running && !managementConnected && daemonStatus !== "Disconnected")

    return {
      ok: true,
      unavailable: false,
      daemonStatus: daemonStatus,
      running: running,
      needsLogin: needsLogin,
      selfName: shortName(selfFqdn),
      selfFqdn: selfFqdn,
      selfIp: selfIp,
      profileName: profileName,
      managementConnected: managementConnected,
      peers: peers
    }
  } catch (e) {
    return { ok: false, unavailable: true, message: "Status error", error: "Failed to parse netbird status" }
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseNetbirdIp: parseNetbirdIp,
    shortName: shortName,
    osIcon: osIcon,
    peerFromDetail: peerFromDetail,
    parseProfiles: parseProfiles,
    parseStatus: parseStatus
  }
}