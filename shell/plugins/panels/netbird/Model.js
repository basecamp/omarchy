// NetBird reports IPs with the mask attached ("100.92.0.2/16").
function stripCidr(value) {
  var text = String(value || "").trim()
  var slash = text.indexOf("/")
  return slash === -1 ? text : text.substring(0, slash)
}

function cleanFqdn(name) {
  var value = String(name || "").trim()
  return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
}

function shortName(fqdn) {
  var clean = cleanFqdn(fqdn)
  if (clean === "") return ""
  return clean.split(".")[0] || clean
}

function displayHostName(fqdn, fallback) {
  var short = shortName(fqdn)
  if (short !== "" && short.toLowerCase() !== "localhost") return short
  return String(fallback || "") || short || "Unknown"
}

// The platform arrives as the Go pair ("linux/amd64"); match its leading segment.
function osIcon(os) {
  var value = String(os || "").toLowerCase().split("/")[0].trim()
  if (value === "linux") return "󰌽"
  if (value === "darwin" || value === "macos" || value === "ios") return "󰀵"
  if (value === "windows") return "󰍲"
  if (value === "android") return "󰀲"
  if (value === "freebsd" || value === "openbsd" || value === "netbsd") return "󰈺"
  return "󰟀"
}

function normalizeDaemonState(text) {
  var value = String(text || "").toLowerCase().replace(/[\s_-]+/g, "")
  if (value === "") return ""
  if (value.indexOf("needslogin") !== -1) return "NeedsLogin"
  if (value.indexOf("loginfailed") !== -1) return "LoginFailed"
  if (value.indexOf("sessionexpired") !== -1) return "SessionExpired"
  if (value.indexOf("failedtostart") !== -1) return "FailedToStart"
  // "disconnected" contains "connected", so rule it out first.
  if (value.indexOf("disconnect") !== -1) return "Disconnected"
  if (value.indexOf("connecting") !== -1) return "Connecting"
  if (value.indexOf("connected") !== -1) return "Connected"
  if (value.indexOf("idle") !== -1) return "Idle"
  return ""
}

// The daemon state moves between releases and is sometimes absent, so read
// whichever field is present and fall back to the management connection. An
// explicit state wins: up-but-logged-out reports NeedsLogin, which is not the
// same as management being down.
function readDaemonState(data) {
  var source = data || {}
  var explicit = normalizeDaemonState(source.daemonStatus || source.status || source.daemonState || source.DaemonStatus)
  if (explicit !== "") return explicit

  var management = source.management || source.Management || {}
  if (management.connected === true) return "Connected"

  var error = String(management.error || management.Error || "")
  if (/needs login|unauthor|not logged in|no peer login|session expired/i.test(error)) return "NeedsLogin"

  return "Disconnected"
}

// Durations arrive as nanosecond integers, or pre-formatted on some releases.
function formatLatency(value) {
  if (typeof value === "number" && isFinite(value) && value > 0) {
    var ms = value / 1000000
    if (ms < 1) return "<1ms"
    if (ms < 10) return (Math.round(ms * 10) / 10) + "ms"
    return Math.round(ms) + "ms"
  }
  var text = String(value || "").trim()
  return text === "0s" ? "" : text
}

// Go's zero time arrives verbatim, in two spellings: "0001-01-01T00:00:00Z"
// and the same instant in a local offset ("0000-12-31T16:07:02-07:52"). Read
// the year, so never-connected reads as never — not as 2000 years ago.
function isNeverTimestamp(value) {
  var text = String(value || "").trim()
  if (text === "") return true
  var year = parseInt(text.slice(0, 4), 10)
  return !isFinite(year) || year <= 1
}

function formatBytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return ""

  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024
    i += 1
  }
  // A decimal earns its place under ten of a unit; past that it is noise.
  return ((n >= 10 || i === 0) ? String(Math.round(n)) : n.toFixed(1)) + " " + units[i]
}

function relativeSince(value, nowMs) {
  if (isNeverTimestamp(value)) return ""

  var then = Date.parse(String(value))
  if (!isFinite(then)) return ""

  var secs = Math.floor((Number(nowMs) - then) / 1000)
  if (secs < 45) return "just now"
  if (secs < 3600) return Math.round(secs / 60) + "m ago"
  if (secs < 86400) return Math.round(secs / 3600) + "h ago"
  return Math.round(secs / 86400) + "d ago"
}

// The tunnel reports itself healthy right up until the SSO session lapses, so
// count the session down and turn urgent inside the last hour.
function sessionExpiry(value, nowMs) {
  var none = { text: "", expired: false, urgent: false }
  if (isNeverTimestamp(value)) return none

  var at = Date.parse(String(value))
  if (!isFinite(at)) return none

  var secs = Math.floor((at - Number(nowMs)) / 1000)
  if (secs <= 0) return { text: "Session expired", expired: true, urgent: true }

  var left
  if (secs < 3600) left = Math.max(1, Math.round(secs / 60)) + "m"
  else if (secs < 86400) left = Math.round(secs / 3600) + "h"
  else left = Math.round(secs / 86400) + "d"

  return { text: "Session expires in " + left, expired: false, urgent: secs < 3600 }
}

// Peers and profiles start folded — the header summary is usually the whole
// answer (the profiles section only exists with more than one profile). Applies
// only when no state file exists; once one does, it is authoritative.
function defaultCollapsedSections() {
  return { peers: true, profiles: true }
}

// Folded sections, stored as a list of names so unknown sections survive a
// round trip.
function parseCollapsedSections(raw) {
  var out = {}
  var text = String(raw || "").trim()
  if (text === "") return out

  try {
    var data = JSON.parse(text)
    var list = data ? (data.collapsed || data.Collapsed) : null
    if (!list || typeof list.length !== "number") return out
    for (var i = 0; i < list.length; i++) {
      var name = String(list[i] || "")
      if (name !== "") out[name] = true
    }
  } catch (e) {
    return {}
  }
  return out
}

// Headers carry their own summary, so a folded section still reports.
function routesSummary(routes) {
  var source = routes && typeof routes.length === "number" ? routes : []
  if (source.length === 0) return ""

  var selected = 0
  for (var i = 0; i < source.length; i++) {
    if (source[i] && source[i].Selected === true) selected++
  }
  return selected + "/" + source.length + " SELECTED"
}

function profilesSummary(selectedProfileName) {
  return String(selectedProfileName || "").toUpperCase()
}

function sectionHeader(label, summary) {
  var detail = String(summary || "")
  return detail === "" ? String(label) : String(label) + " · " + detail
}

function collapsedSectionsFile(collapsed) {
  var names = []
  var source = collapsed || {}
  for (var key in source) {
    if (source[key] === true) names.push(key)
  }
  names.sort()
  return { version: 1, collapsed: names }
}

function wireguardMode(usesKernelInterface) {
  if (usesKernelInterface === true) return "kernel"
  if (usesKernelInterface === false) return "userspace"
  // An absent field is unknown, not userspace; healthRows omits the row.
  return ""
}

function connectionLabel(peer) {
  if (!peer || peer.Online !== true) return String((peer && peer.Status) || "Disconnected")
  var parts = []
  if (peer.Relayed === true) parts.push("Relayed")
  else if (peer.ConnectionType !== "") parts.push(peer.ConnectionType)
  if (peer.Latency !== "") parts.push(peer.Latency)
  return parts.join(" · ")
}

function peerFromStatus(peer) {
  var source = peer || {}
  var fqdn = cleanFqdn(source.fqdn || source.Fqdn || source.dnsLabel || "")
  var ip = stripCidr(source.netbirdIp || source.NetbirdIp || source.ip || "")
  var status = String(source.status || source.Status || "").trim()
  var connectionType = String(source.connectionType || source.ConnectionType || "").trim()

  return {
    id: String(source.publicKey || source.PublicKey || fqdn || ip),
    HostName: displayHostName(fqdn, ip),
    DisplayName: displayHostName(fqdn, ip),
    Fqdn: fqdn,
    IP: ip,
    Status: status || "Disconnected",
    Online: status.toLowerCase() === "connected",
    OS: String(source.os || source.OS || ""),
    ConnectionType: connectionType,
    Relayed: source.relayed === true || connectionType.toLowerCase() === "relayed",
    Latency: formatLatency(source.latency !== undefined ? source.latency : source.Latency),
    LastHandshake: String(source.lastWireguardHandshake || source.lastStatusUpdate || ""),
    TransferSent: Number(source.transferSent || source.TransferSent || 0),
    TransferReceived: Number(source.transferReceived || source.TransferReceived || 0)
  }
}

// The peer row's second line. Idle is the normal case, so "never" is an
// answer, not an error.
function peerActivity(peer, nowMs) {
  var source = peer || {}
  var sent = formatBytes(source.TransferSent)
  var received = formatBytes(source.TransferReceived)
  var seen = relativeSince(source.LastHandshake, nowMs)

  var parts = []
  if (received !== "") parts.push("↓ " + received)
  if (sent !== "") parts.push("↑ " + sent)
  if (seen !== "") parts.push("last seen " + seen)
  else if (parts.length === 0) parts.push("never connected")

  return parts.join(" · ")
}

// NetBird serves DNS for its own domains through nameserver groups; the DNS
// warning keys off them.
function parseNameserverGroups(data) {
  var source = (data && (data.nsServerGroups || data.NSServerGroups || data.nameserverGroups)) || []
  if (!source || typeof source.length !== "number") return []

  var groups = []
  for (var i = 0; i < source.length; i++) {
    var group = source[i] || {}
    var servers = []
    var rawServers = group.servers || group.Servers || []
    if (rawServers && typeof rawServers.length === "number") {
      for (var s = 0; s < rawServers.length; s++) {
        var server = rawServers[s]
        // Servers arrive either as plain strings or as {ip, port} objects.
        var address = typeof server === "string" ? server : String((server && (server.ip || server.IP)) || "")
        address = stripCidr(address)
        if (address !== "") servers.push(address)
      }
    }

    var domains = []
    var rawDomains = group.domains || group.Domains || []
    if (rawDomains && typeof rawDomains.length === "number") {
      for (var d = 0; d < rawDomains.length; d++) {
        var domain = String(rawDomains[d] || "").trim()
        if (domain !== "") domains.push(domain)
      }
    }

    groups.push({
      Servers: servers,
      Domains: domains,
      Enabled: group.enabled !== false && group.Enabled !== false
    })
  }
  return groups
}

function hasManagedDns(groups) {
  var values = groups && typeof groups.length === "number" ? groups : []
  for (var i = 0; i < values.length; i++) {
    if (values[i] && values[i].Enabled === true) return true
  }
  return false
}

// NetworkManager applies the [global-dns-domain-*] block `omarchy dns` writes
// ahead of every other DNS source, including NetBird's split DNS — so a pinned
// provider breaks NetBird's domains while NetBird reports healthy.
function dnsOverrideWarning(managedDns, systemDnsProvider) {
  if (managedDns !== true) return ""
  var provider = String(systemDnsProvider || "").trim()
  if (provider === "" || provider === "DHCP") return ""
  return provider
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Disconnected" }

  try {
    var data = JSON.parse(text)
    var backendState = readDaemonState(data)
    var management = data.management || data.Management || {}
    var signal = data.signal || data.Signal || {}
    var relays = data.relays || data.Relays || {}

    var rawPeers = []
    var peersNode = data.peers || data.Peers || {}
    if (peersNode && typeof peersNode.length === "number") rawPeers = peersNode
    else if (peersNode && peersNode.details) rawPeers = peersNode.details
    else if (peersNode && peersNode.Details) rawPeers = peersNode.Details

    var peers = []
    for (var i = 0; i < rawPeers.length; i++) peers.push(peerFromStatus(rawPeers[i]))

    // Connected first, then by name. Idle peers are the norm on a NetBird
    // network, so they stay listed.
    peers.sort(function(a, b) {
      if (a.Online !== b.Online) return a.Online ? -1 : 1
      return String(a.HostName).localeCompare(String(b.HostName))
    })

    var connected = 0
    for (var j = 0; j < peers.length; j++) if (peers[j].Online) connected++

    var fqdn = cleanFqdn(data.fqdn || data.Fqdn || "")
    var selfIp = stripCidr(data.netbirdIp || data.NetbirdIp || "")
    var nameserverGroups = parseNameserverGroups(data)

    return {
      ok: true,
      unavailable: false,
      backendState: backendState,
      running: backendState === "Connected",
      needsLogin: backendState === "NeedsLogin" || backendState === "LoginFailed" || backendState === "SessionExpired",
      // Logged out reports no fqdn and no IP; return "" so the hero can fall
      // back to its own label.
      selfName: fqdn === "" && selfIp === "" ? "" : displayHostName(fqdn, selfIp),
      selfFqdn: fqdn,
      selfIp: selfIp,
      managementUrl: String(management.url || management.URL || ""),
      managementConnected: management.connected === true,
      managementError: String(management.error || management.Error || ""),
      signalUrl: String(signal.url || signal.URL || ""),
      signalConnected: signal.connected === true,
      signalError: String(signal.error || signal.Error || ""),
      relaysAvailable: Number(relays.available || relays.Available || 0),
      relaysTotal: Number(relays.total || relays.Total || 0),
      wireguardMode: wireguardMode(data.usesKernelInterface === undefined
        ? data.UsesKernelInterface
        : data.usesKernelInterface),
      wireguardPort: Number(data.wireguardPort || data.WireguardPort || 0),
      sessionExpiresAt: String(data.sessionExpiresAt || data.SessionExpiresAt || ""),
      peers: peers,
      connectedPeers: connected,
      totalPeers: peers.length,
      nameserverGroups: nameserverGroups,
      managedDns: hasManagedDns(nameserverGroups)
    }
  } catch (e) {
    return { ok: false, unavailable: true, message: "Status error", error: "Failed to parse netbird status" }
  }
}

// A dual-stack exit node carries both default routes in one field
// ("0.0.0.0/0, ::/0"), so test the parts rather than the whole string.
function isExitNodeNetwork(network) {
  var parts = String(network || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var value = parts[i].trim()
    if (value === "0.0.0.0/0" || value === "::/0") return true
  }
  return false
}

function routeSelected(status) {
  var value = String(status || "").trim()
  if (value === "") return false
  // "Not Selected" contains "selected", so rule the negative out first.
  if (/^(not|un)[\s-]*(selected|enabled)/i.test(value)) return false
  return /selected|enabled|true|active/i.test(value)
}

function normalizeRoute(route) {
  var source = route || {}
  var id = String(source.id || source.ID || source.Id || source.name || source.Name || "").trim()
  var network = String(source.network || source.Network || source.range || source.Range || "").trim()

  var domains = []
  var rawDomains = source.domains || source.Domains || []
  if (rawDomains && typeof rawDomains.length === "number") {
    for (var i = 0; i < rawDomains.length; i++) {
      var domain = String(rawDomains[i] || "").trim()
      if (domain !== "") domains.push(domain)
    }
  }

  var selected = source.selected !== undefined ? source.selected === true
    : (source.Selected !== undefined ? source.Selected === true : routeSelected(source.status || source.Status))

  var exitNode = isExitNodeNetwork(network)

  return {
    id: id || network,
    Network: network,
    Domains: domains,
    Selected: selected,
    ExitNode: exitNode,
    DisplayName: id || network || "Route",
    Detail: exitNode ? "Exit node" : (domains.length > 0 ? domains.join(", ") : network)
  }
}

// Routes print as indented "- ID: / Network: / Status:" blocks; newer releases
// say "networks" and "Range". Match the keys, not the headings.
function parseRoutesText(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var routes = []
  var current = null

  function flush() {
    if (current && (current.id !== "" || current.network !== "")) {
      routes.push(normalizeRoute({
        id: current.id,
        network: current.network,
        domains: current.domains,
        status: current.status
      }))
    }
    current = null
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]

    var idMatch = line.match(/^\s*-?\s*(?:ID|Id)\s*:\s*(.+)$/)
    if (idMatch) {
      flush()
      current = { id: idMatch[1].trim(), network: "", domains: [], status: "" }
      continue
    }
    if (!current) continue

    var networkMatch = line.match(/^\s*(?:Network|Range|Networks)\s*:\s*(.+)$/i)
    if (networkMatch) {
      current.network = networkMatch[1].trim()
      continue
    }

    var domainMatch = line.match(/^\s*Domains?\s*:\s*(.+)$/i)
    if (domainMatch) {
      var parts = domainMatch[1].split(",")
      for (var d = 0; d < parts.length; d++) {
        var domain = parts[d].trim()
        if (domain !== "" && domain !== "-") current.domains.push(domain)
      }
      continue
    }

    var statusMatch = line.match(/^\s*(?:Status|Selected)\s*:\s*(.+)$/i)
    if (statusMatch) current.status = statusMatch[1].trim()
  }

  flush()
  return routes
}

function parseRoutes(raw) {
  var text = String(raw || "").trim()
  if (text === "") return []

  if (text.charAt(0) === "[" || text.charAt(0) === "{") {
    try {
      var data = JSON.parse(text)
      var list = data
      if (data && typeof data.length !== "number") list = data.routes || data.Routes || data.networks || data.Networks || []
      if (!list || typeof list.length !== "number") return []

      var routes = []
      for (var i = 0; i < list.length; i++) routes.push(normalizeRoute(list[i]))
      return routes
    } catch (e) {
      return []
    }
  }

  return parseRoutesText(text)
}

// Exit nodes first — the row people open this section for.
function sortRoutes(routes) {
  var values = []
  var source = routes && typeof routes.length === "number" ? routes : []
  for (var i = 0; i < source.length; i++) values.push(source[i])
  values.sort(function(a, b) {
    if (a.ExitNode !== b.ExitNode) return a.ExitNode ? -1 : 1
    return String(a.DisplayName).localeCompare(String(b.DisplayName))
  })
  return values
}

function loginPlan(needsLogin, authUrl) {
  var url = String(authUrl || "").trim()
  if (needsLogin === true && /^https?:\/\//.test(url)) {
    return { authUrl: url, command: [] }
  }
  return { authUrl: "", command: ["netbird", "up"] }
}

function profileLabel(profile) {
  if (!profile) return "Unknown profile"
  if (profile.name) return String(profile.name)
  if (profile.email) return String(profile.email)
  return "Unknown profile"
}

// No release ships `profile list --json`, so the padded table is the interface.
// Names are free-form ("work laptop"), so slice rows at the header's column
// offsets rather than splitting on whitespace.
function parseProfilesText(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var columns = null
  var profiles = []
  var selected = null

  for (var i = 0; i < lines.length; i++) {
    var line = String(lines[i] || "")
    if (line.trim() === "") continue

    if (columns === null) {
      // Read the columns off the header, and treat anything before it as
      // noise. --show-id puts an ID column ahead of NAME.
      if (!/^\s*(ID|NAME)\b/i.test(line) || !/\bNAME\b/i.test(line)) continue
      columns = []
      var header = /\S+/g
      var match
      while ((match = header.exec(line)) !== null) {
        columns.push({ name: match[0].toUpperCase(), start: match.index })
      }
      continue
    }

    var row = {}
    for (var c = 0; c < columns.length; c++) {
      var end = c + 1 < columns.length ? columns[c + 1].start : line.length
      row[columns[c].name] = line.slice(columns[c].start, end).trim()
    }

    var name = String(row.NAME || "")
    if (name === "") continue

    var active = String(row.ACTIVE || "")
    var profile = {
      // Names may be duplicated; the ID (from --show-id) is what selects.
      id: String(row.ID || ""),
      name: name,
      email: String(row.EMAIL || ""),
      selected: active !== "" && active !== "-" && !/^(false|no)$/i.test(active)
    }
    profiles.push(profile)
    if (profile.selected) selected = profile
  }

  return {
    profiles: profiles,
    selectedProfileName: selected ? selected.name : "",
    selectedProfileLabel: selected ? profileLabel(selected) : ""
  }
}

function parseProfiles(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { profiles: [], selectedProfileName: "", selectedProfileLabel: "" }

  if (text.charAt(0) !== "[" && text.charAt(0) !== "{") return parseProfilesText(text)

  try {
    var parsed = JSON.parse(text)
    var list = parsed
    if (parsed && typeof parsed.length !== "number") list = parsed.profiles || parsed.Profiles || []
    if (!list || typeof list.length !== "number") return { profiles: [], selectedProfileName: "", selectedProfileLabel: "" }

    var profiles = []
    var selected = null
    for (var i = 0; i < list.length; i++) {
      var raw_profile = list[i] || {}
      var profile = {
        id: String(raw_profile.id || raw_profile.ID || raw_profile.Id || ""),
        name: String(raw_profile.name || raw_profile.Name || ""),
        email: String(raw_profile.email || raw_profile.Email || raw_profile.username || raw_profile.Username || ""),
        selected: raw_profile.selected === true || raw_profile.Selected === true || raw_profile.active === true || raw_profile.Active === true
      }
      if (profile.name === "") continue
      profiles.push(profile)
      if (profile.selected) selected = profile
    }

    return {
      profiles: profiles,
      selectedProfileName: selected ? selected.name : "",
      selectedProfileLabel: selected ? profileLabel(selected) : ""
    }
  } catch (e) {
    return { profiles: [], selectedProfileName: "", selectedProfileLabel: "" }
  }
}

// Profiles and JSON routes are newer than some installed CLIs; recognise the
// refusal rather than surfacing it as an error.
function isUnsupportedCommand(text) {
  var value = String(text || "")
  return /unknown command|unknown flag|unknown shorthand flag|flag provided but not defined|unknown subcommand/i.test(value)
}

function isPermissionError(text) {
  var value = String(text || "")
  return /permission denied|connection refused|failed to connect|dial unix|no such file or directory/i.test(value)
}

var CLOUD_ADMIN_URL = "https://app.netbird.io/peers"

// The admin URL a peer joined with lives in root-only daemon config, so derive
// the console from the management URL that status reports. The cloud splits
// api/app hostnames; self-hosted serves both from one origin.
function urlHost(url) {
  var value = String(url || "").trim()
  if (value === "") return ""

  var host = value.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").split("/")[0]
  // Leave an IPv6 literal's brackets alone; only a trailing :port is noise here.
  if (host.charAt(0) === "[") {
    var closing = host.indexOf("]")
    if (closing !== -1) host = host.slice(0, closing + 1)
  } else {
    host = host.split(":")[0]
  }
  return host
}

// Host plus any non-default port; only the https default is dropped.
function urlHostPort(url) {
  var value = String(url || "").trim()
  if (value === "") return ""
  return value.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").split("/")[0]
}

function urlScheme(url) {
  var match = String(url || "").trim().match(/^([a-z][a-z0-9+.-]*):\/\//i)
  return match ? match[1].toLowerCase() : "https"
}

function adminConsoleUrl(managementUrl) {
  var host = urlHost(managementUrl)
  if (host === "") return CLOUD_ADMIN_URL
  if (/(^|\.)netbird\.io$/i.test(host)) return CLOUD_ADMIN_URL

  // Keep an explicit http; :443 is only noise under https.
  var scheme = urlScheme(managementUrl)
  var origin = urlHostPort(managementUrl)
  if (scheme === "https" && origin.slice(-4) === ":443") origin = origin.slice(0, -4)
  return scheme + "://" + origin + "/peers"
}

// Management, signal, and relays fail independently — "connected but nothing
// works" is usually a relay. Lay them out and flag what is down.
function healthRows(state) {
  var s = state || {}
  var rows = []

  // The daemon reports why a connection is down; that beats a bare "offline".
  rows.push({
    label: "Management",
    value: urlHost(s.managementUrl) || "unknown",
    detail: s.managementConnected === true ? "connected" : (String(s.managementError || "") || "offline"),
    warn: s.managementConnected !== true
  })
  rows.push({
    label: "Signal",
    value: urlHost(s.signalUrl) || "unknown",
    detail: s.signalConnected === true ? "connected" : (String(s.signalError || "") || "offline"),
    warn: s.signalConnected !== true
  })

  var total = Number(s.relaysTotal || 0)
  var available = Number(s.relaysAvailable || 0)
  rows.push({
    label: "Relays",
    value: available + "/" + total,
    detail: total === 0 ? "none configured" : "available",
    warn: total > 0 && available === 0
  })

  var mode = String(s.wireguardMode || "")
  var port = Number(s.wireguardPort || 0)
  if (mode !== "") {
    rows.push({
      label: "WireGuard",
      value: mode,
      detail: port > 0 ? "port " + port : "",
      warn: false
    })
  }

  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    stripCidr: stripCidr,
    cleanFqdn: cleanFqdn,
    shortName: shortName,
    displayHostName: displayHostName,
    osIcon: osIcon,
    normalizeDaemonState: normalizeDaemonState,
    readDaemonState: readDaemonState,
    formatLatency: formatLatency,
    connectionLabel: connectionLabel,
    peerFromStatus: peerFromStatus,
    parseNameserverGroups: parseNameserverGroups,
    hasManagedDns: hasManagedDns,
    dnsOverrideWarning: dnsOverrideWarning,
    parseStatus: parseStatus,
    isExitNodeNetwork: isExitNodeNetwork,
    routeSelected: routeSelected,
    normalizeRoute: normalizeRoute,
    parseRoutesText: parseRoutesText,
    parseRoutes: parseRoutes,
    sortRoutes: sortRoutes,
    loginPlan: loginPlan,
    profileLabel: profileLabel,
    parseProfiles: parseProfiles,
    isUnsupportedCommand: isUnsupportedCommand,
    isPermissionError: isPermissionError,
    adminConsoleUrl: adminConsoleUrl,
    isNeverTimestamp: isNeverTimestamp,
    formatBytes: formatBytes,
    relativeSince: relativeSince,
    sessionExpiry: sessionExpiry,
    wireguardMode: wireguardMode,
    peerActivity: peerActivity,
    urlHost: urlHost,
    urlHostPort: urlHostPort,
    urlScheme: urlScheme,
    healthRows: healthRows,
    parseProfilesText: parseProfilesText,
    defaultCollapsedSections: defaultCollapsedSections,
    parseCollapsedSections: parseCollapsedSections,
    collapsedSectionsFile: collapsedSectionsFile,
    routesSummary: routesSummary,
    profilesSummary: profilesSummary,
    sectionHeader: sectionHeader
  }
}
