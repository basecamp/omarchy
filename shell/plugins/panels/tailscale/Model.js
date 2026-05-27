function filterIPv4(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^100\./.test(ip)) result.push(ip)
  }
  return result
}

function filterIPv6(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^fd7a:115c:a1e0:/i.test(ip)) result.push(ip)
  }
  return result
}

function cleanDnsName(name) {
  var value = String(name || "")
  return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
}

function shortDnsName(name) {
  var clean = cleanDnsName(name)
  if (clean === "") return ""
  return clean.split(".")[0] || clean
}

function displayHostName(hostName, dnsName) {
  var host = String(hostName || "")
  if (host !== "" && host.toLowerCase() !== "localhost") return host
  return shortDnsName(dnsName) || host || "Unknown"
}

function osIcon(os) {
  var value = String(os || "").toLowerCase()
  if (value === "linux") return "󰌽"
  if (value === "macos" || value === "ios") return "󰀵"
  if (value === "windows") return "󰍲"
  if (value === "android") return "󰀲"
  return "󰟀"
}

function accountLabel(account) {
  if (!account) return "Unknown account"
  if (account.nickname) return String(account.nickname)
  if (account.tailnet) return String(account.tailnet)
  if (account.account) return String(account.account)
  return String(account.id || "Unknown account")
}

function peerFromStatus(id, peer) {
  return {
    id: id,
    HostName: displayHostName(peer.HostName, peer.DNSName),
    DNSName: cleanDnsName(peer.DNSName),
    TailscaleIPs: filterIPv4(peer.TailscaleIPs || []),
    TailscaleIPv6: filterIPv6(peer.TailscaleIPs || []),
    Online: peer.Online === true,
    OS: String(peer.OS || ""),
    Tags: peer.Tags || [],
    ExitNodeOption: peer.ExitNodeOption === true,
    ExitNode: peer.ExitNode === true
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Disconnected" }

  try {
    var data = JSON.parse(text)
    var backendState = String(data.BackendState || "Unknown")
    var self = data.Self || {}
    var selfIps = filterIPv4(self.TailscaleIPs || data.TailscaleIPs || [])
    var peers = []
    var exitNodes = []
    var rawPeers = data.Peer || {}

    for (var id in rawPeers) {
      var peer = rawPeers[id] || {}
      var normalized = peerFromStatus(id, peer)
      if (normalized.Online) {
        peers.push(normalized)
        if (normalized.ExitNodeOption) exitNodes.push(normalized)
      }
    }

    peers.sort(function(a, b) {
      return String(a.HostName).localeCompare(String(b.HostName))
    })
    exitNodes.sort(function(a, b) {
      return String(a.HostName).localeCompare(String(b.HostName))
    })

    return {
      ok: true,
      unavailable: false,
      backendState: backendState,
      running: backendState === "Running",
      needsLogin: backendState === "NeedsLogin",
      authUrl: String(data.AuthURL || ""),
      selfName: displayHostName(self.HostName, self.DNSName),
      selfDnsName: cleanDnsName(self.DNSName),
      selfIp: selfIps.length > 0 ? selfIps[0] : "",
      peers: peers,
      exitNodes: exitNodes
    }
  } catch (e) {
    return { ok: false, unavailable: true, message: "Status error", error: "Failed to parse tailscale status" }
  }
}

function parseAccounts(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }

  try {
    var parsed = JSON.parse(text)
    var next = []
    var selected = null
    if (parsed && typeof parsed.length === "number") {
      for (var i = 0; i < parsed.length; i++) {
        var rawAccount = parsed[i] || {}
        var account = {
          id: String(rawAccount.id || rawAccount.ID || ""),
          nickname: String(rawAccount.nickname || rawAccount.Nickname || rawAccount.name || rawAccount.Name || ""),
          tailnet: String(rawAccount.tailnet || rawAccount.Tailnet || ""),
          account: String(rawAccount.account || rawAccount.Account || rawAccount.loginName || rawAccount.LoginName || rawAccount.user || rawAccount.User || ""),
          selected: rawAccount.selected === true || rawAccount.Selected === true
        }
        next.push(account)
        if (account.selected === true) selected = account
      }
    }
    return {
      accounts: next,
      selectedAccountId: selected ? String(selected.id || "") : "",
      selectedAccountLabel: selected ? accountLabel(selected) : ""
    }
  } catch (e) {
    return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    filterIPv4: filterIPv4,
    filterIPv6: filterIPv6,
    cleanDnsName: cleanDnsName,
    shortDnsName: shortDnsName,
    displayHostName: displayHostName,
    osIcon: osIcon,
    accountLabel: accountLabel,
    peerFromStatus: peerFromStatus,
    parseStatus: parseStatus,
    parseAccounts: parseAccounts
  }
}
