// NetBird's IP arrives with the network mask attached ("100.92.0.2/16"), which
// is not what anybody wants to paste into an ssh command.
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

// NetBird reports the Go platform pair ("linux/amd64"), so match the leading
// segment rather than the whole string.
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
  if (value.indexOf("failedtostart") !== -1) return "FailedToStart"
  if (value.indexOf("connecting") !== -1) return "Connecting"
  if (value.indexOf("connected") !== -1) return "Connected"
  if (value.indexOf("disconnected") !== -1) return "Disconnected"
  if (value.indexOf("idle") !== -1) return "Idle"
  return ""
}

// NetBird has moved the daemon state around between releases and does not
// always carry one in the JSON, so read whichever field is present and fall
// back to what the management connection says. An explicit state always wins:
// a daemon that is up but logged out reports NeedsLogin while management is
// simply not connected, and those two mean very different things to the user.
function readDaemonState(data) {
  var source = data || {}
  var explicit = normalizeDaemonState(source.daemonStatus || source.status || source.daemonState || source.DaemonStatus)
  if (explicit !== "") return explicit

  var management = source.management || source.Management || {}
  if (management.connected === true) return "Connected"

  var error = String(management.error || management.Error || "")
  if (/needs login|unauthor|not logged in|no peer login/i.test(error)) return "NeedsLogin"

  return "Disconnected"
}

// Go marshals a duration as an integer count of nanoseconds, but some NetBird
// releases hand back the pre-formatted string instead. Take either.
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
    LastHandshake: String(source.lastWireguardHandshake || source.lastStatusUpdate || "")
  }
}

// NetBird hands DNS for its own domains to nameserver groups. They only work
// if something on the box actually routes those domains at NetBird, which is
// what the DNS warning in the panel is about.
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

// `omarchy dns <provider>` writes NetworkManager a [global-dns-domain-*]
// block, and NetworkManager documents that as overriding every other source of
// DNS — including the split DNS a VPN installs. So a machine pinned to
// Cloudflare or Google resolves nothing NetBird serves for its own domains,
// while NetBird itself still reports a healthy connection. Warn rather than
// quietly disagree with the user's DNS choice.
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

    // Connected peers first, then alphabetically. Unlike a tailnet, a NetBird
    // network routinely carries peers that are simply idle rather than gone,
    // so hiding them would hide most of the network.
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
      needsLogin: backendState === "NeedsLogin" || backendState === "LoginFailed",
      selfName: displayHostName(fqdn, selfIp),
      selfFqdn: fqdn,
      selfIp: selfIp,
      managementUrl: String(management.url || management.URL || ""),
      managementConnected: management.connected === true,
      managementError: String(management.error || management.Error || ""),
      signalConnected: signal.connected === true,
      relaysAvailable: Number(relays.available || relays.Available || 0),
      relaysTotal: Number(relays.total || relays.Total || 0),
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

function isExitNodeNetwork(network) {
  var value = String(network || "").trim()
  return value === "0.0.0.0/0" || value === "::/0"
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

// NetBird prints routes as indented "- ID: / Network: / Status:" blocks, and
// newer releases print the same shape under "networks" with "Range" instead of
// "Network". Read the keys rather than the headings so either one lands.
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

// Exit nodes first, then everything else by name — the exit node is the choice
// people come to this section to make.
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

function parseProfiles(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { profiles: [], selectedProfileName: "", selectedProfileLabel: "" }

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

// Profiles and JSON route output landed in NetBird after the versions Omarchy
// may find on a machine. Rather than surfacing an error for a subcommand the
// installed CLI has never heard of, recognise the refusal and stop asking.
function isUnsupportedCommand(text) {
  var value = String(text || "")
  return /unknown command|unknown flag|unknown shorthand flag|flag provided but not defined|unknown subcommand/i.test(value)
}

function isPermissionError(text) {
  var value = String(text || "")
  return /permission denied|connection refused|failed to connect|dial unix|no such file or directory/i.test(value)
}

var CLOUD_ADMIN_URL = "https://app.netbird.io/peers"

// The admin panel URL a peer was joined with is only kept in
// /var/lib/netbird/<profile>.json, which is root-only, so the panel cannot read
// it back. The management URL does come through `netbird status --json`, and a
// self-hosted deployment serves its dashboard from the same host, so derive the
// console from that and special-case the cloud, whose API and dashboard live on
// different hostnames.
function adminConsoleUrl(managementUrl) {
  var value = String(managementUrl || "").trim()
  if (value === "") return CLOUD_ADMIN_URL

  var withoutScheme = value.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")
  var host = withoutScheme.split("/")[0]
  // Leave an IPv6 literal's brackets alone; only a trailing :port is noise here.
  if (host.charAt(0) === "[") {
    var closing = host.indexOf("]")
    if (closing !== -1) host = host.slice(0, closing + 1)
  } else {
    host = host.split(":")[0]
  }

  if (host === "") return CLOUD_ADMIN_URL
  if (/(^|\.)netbird\.io$/i.test(host)) return CLOUD_ADMIN_URL
  return "https://" + host + "/peers"
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
    adminConsoleUrl: adminConsoleUrl
  }
}
