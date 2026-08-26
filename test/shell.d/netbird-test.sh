#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const netbird = requireFromRoot('shell/plugins/panels/netbird/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/netbird/Panel.qml', 'utf8')
const serviceSource = fs.readFileSync(root + '/shell/plugins/panels/netbird/Service.qml', 'utf8')

assert(/function toggleNetbird\(\): string \{ netbird\.toggleNetbird\(\); return "ok" \}/.test(panelSource), 'netbird exposes the connection toggle over IPC')

assertEqual(netbird.stripCidr('100.92.0.2/16'), '100.92.0.2', 'netbird strips the mask off its own address')
assertEqual(netbird.stripCidr('100.92.0.2'), '100.92.0.2', 'netbird leaves a bare address alone')
assertEqual(netbird.cleanFqdn('host.netbird.cloud.'), 'host.netbird.cloud', 'netbird strips trailing DNS dot')
assertEqual(netbird.shortName('host.netbird.cloud.'), 'host', 'netbird shortens a domain name to its first label')
assertEqual(netbird.displayHostName('', '100.92.0.7'), '100.92.0.7', 'netbird falls back to the IP without a domain name')
assertEqual(netbird.displayHostName('localhost.netbird.cloud', '100.92.0.7'), '100.92.0.7', 'netbird refuses localhost as a peer name')

// Go marshals a duration to nanoseconds; some releases pre-format it instead.
assertEqual(netbird.formatLatency(12000000), '12ms', 'netbird formats a nanosecond latency')
assertEqual(netbird.formatLatency(1400000), '1.4ms', 'netbird keeps one decimal under ten milliseconds')
assertEqual(netbird.formatLatency(400000), '<1ms', 'netbird floors a sub-millisecond latency')
assertEqual(netbird.formatLatency('48ms'), '48ms', 'netbird passes a pre-formatted latency through')
assertEqual(netbird.formatLatency('0s'), '', 'netbird drops a zero latency')

assertEqual(netbird.osIcon('linux/amd64'), netbird.osIcon('linux'), 'netbird reads the platform pair as its leading segment')
assert(netbird.osIcon('darwin/arm64') === netbird.osIcon('macos'), 'netbird maps darwin to the Apple glyph')

const status = netbird.parseStatus(JSON.stringify({
  management: { url: 'https://api.netbird.io:443', connected: true },
  signal: { url: 'https://signal.netbird.io:443', connected: true },
  relays: { total: 2, available: 2 },
  netbirdIp: '100.92.0.2/16',
  fqdn: 'my-laptop.netbird.cloud',
  nsServerGroups: [
    { servers: [{ ip: '100.92.0.1', port: 53 }], domains: ['netbird.cloud'], enabled: true }
  ],
  peers: {
    total: 3,
    connected: 2,
    details: [
      { fqdn: 'zed.netbird.cloud', netbirdIp: '100.92.0.9/16', status: 'Connected', os: 'linux/amd64', connectionType: 'P2P', latency: 12000000, publicKey: 'k1' },
      { fqdn: 'phone.netbird.cloud', netbirdIp: '100.92.0.3/16', status: 'Idle', os: 'android', publicKey: 'k2' },
      { fqdn: 'alpha.netbird.cloud', netbirdIp: '100.92.0.4/16', status: 'Connected', os: 'darwin/arm64', connectionType: 'Relayed', relayed: true, latency: '48ms', publicKey: 'k3' }
    ]
  }
}))

assert(status.ok && status.running, 'netbird parses a connected status')
assertEqual(status.backendState, 'Connected', 'netbird derives the daemon state from the management connection')
assertEqual(status.selfIp, '100.92.0.2', 'netbird parses this machine IP without its mask')
assertEqual(status.selfName, 'my-laptop', 'netbird names this machine by its short domain name')
assertDeepEqual(
  status.peers.map(peer => peer.HostName),
  ['alpha', 'zed', 'phone'],
  'netbird sorts connected peers first and keeps idle ones'
)
assertDeepEqual(status.peers.map(peer => peer.Online), [true, true, false], 'netbird records which peers are connected')
assertEqual(status.connectedPeers, 2, 'netbird counts connected peers')
assertEqual(status.totalPeers, 3, 'netbird counts every peer')
assertEqual(status.peers[0].IP, '100.92.0.4', 'netbird strips the mask off a peer address')
assertEqual(netbird.connectionLabel(status.peers[0]), 'Relayed · 48ms', 'netbird labels a relayed peer with its latency')
assertEqual(netbird.connectionLabel(status.peers[1]), 'P2P · 12ms', 'netbird labels a direct peer with its latency')
assertEqual(netbird.connectionLabel(status.peers[2]), 'Idle', 'netbird labels an idle peer with its status')

assert(status.managedDns, 'netbird reports that it is serving DNS for its own domains')
assertDeepEqual(status.nameserverGroups[0].Servers, ['100.92.0.1'], 'netbird reads nameserver group servers given as objects')
assertDeepEqual(status.nameserverGroups[0].Domains, ['netbird.cloud'], 'netbird reads nameserver group domains')
assert(
  netbird.hasManagedDns([{ Enabled: false }, { Enabled: true }]),
  'netbird counts any enabled nameserver group as managed DNS'
)
assert(!netbird.hasManagedDns([{ Enabled: false }]), 'netbird ignores disabled nameserver groups')
assertDeepEqual(
  netbird.parseNameserverGroups({ nsServerGroups: [{ servers: ['100.92.0.1/32'], domains: [] }] })[0].Servers,
  ['100.92.0.1'],
  'netbird reads nameserver group servers given as strings'
)

// The whole point of the DNS notice: NetworkManager's global-dns block wins
// over the split DNS NetBird installs, so a pinned provider silently breaks it.
assertEqual(netbird.dnsOverrideWarning(true, 'Cloudflare'), 'Cloudflare', 'netbird warns when a pinned provider overrides its DNS')
assertEqual(netbird.dnsOverrideWarning(true, 'Custom'), 'Custom', 'netbird warns about a custom provider too')
assertEqual(netbird.dnsOverrideWarning(true, 'DHCP'), '', 'netbird stays quiet when DNS comes from DHCP')
assertEqual(netbird.dnsOverrideWarning(false, 'Cloudflare'), '', 'netbird stays quiet when it serves no DNS of its own')
assertEqual(netbird.dnsOverrideWarning(true, ''), '', 'netbird stays quiet until the provider is known')

// A logged-out daemon still answers with usable JSON, and the panel has to
// read it rather than treating the non-zero exit as an outage.
const loggedOut = netbird.parseStatus(JSON.stringify({ status: 'NeedsLogin', management: { connected: false } }))
assert(loggedOut.needsLogin && !loggedOut.running, 'netbird parses an explicit NeedsLogin state')
assert(/stdout\.trim\(\) !== ""/.test(serviceSource), 'netbird reads status output before treating an exit code as failure')

const derivedLogin = netbird.parseStatus(JSON.stringify({ management: { connected: false, error: 'peer is not logged in' } }))
assert(derivedLogin.needsLogin, 'netbird infers NeedsLogin from a management error when no state is carried')

const stopped = netbird.parseStatus(JSON.stringify({ management: { connected: false } }))
assert(stopped.ok && !stopped.running && !stopped.needsLogin, 'netbird treats an unexplained disconnect as disconnected')

assertEqual(netbird.normalizeDaemonState('needs login'), 'NeedsLogin', 'netbird normalizes a spaced daemon state')
assertEqual(netbird.normalizeDaemonState('LOGIN_FAILED'), 'LoginFailed', 'netbird normalizes an underscored daemon state')
assertEqual(netbird.normalizeDaemonState('banana'), '', 'netbird reports nothing for an unknown daemon state')

const routesText = netbird.parseRoutes(`Available Routes:

  - ID: chicago-exit
    Network: 0.0.0.0/0
    Status: Not Selected

  - ID: office-lan
    Network: 10.10.0.0/16
    Status: Selected

  - ID: internal-apps
    Network: 172.16.0.0/12
    Domains: apps.internal, wiki.internal
    Status: Not Selected
`)

assertDeepEqual(
  routesText.map(route => route.id),
  ['chicago-exit', 'office-lan', 'internal-apps'],
  'netbird parses the text route listing'
)
assert(routesText[0].ExitNode, 'netbird recognizes a default route as an exit node')
assert(!routesText[0].Selected, 'netbird does not read "Not Selected" as selected')
assert(routesText[1].Selected, 'netbird reads a selected route')
assertEqual(routesText[1].Detail, '10.10.0.0/16', 'netbird details a plain route with its network')
assertEqual(routesText[0].Detail, 'Exit node', 'netbird details an exit node as such')
assertDeepEqual(routesText[2].Domains, ['apps.internal', 'wiki.internal'], 'netbird parses route domains')
assertEqual(routesText[2].Detail, 'apps.internal, wiki.internal', 'netbird details a domain route with its domains')

// Newer releases print the same blocks under "networks" with a Range key.
const networksText = netbird.parseRoutes(`Available Networks:

  - ID: datacenter
    Range: 10.0.0.0/8
    Status: Selected
`)
assertEqual(networksText.length, 1, 'netbird parses the networks listing')
assertEqual(networksText[0].Network, '10.0.0.0/8', 'netbird reads Range as the network')
assert(networksText[0].Selected, 'netbird reads a selected network')

assertDeepEqual(
  netbird.parseRoutes('[{"id":"exit-1","range":"0.0.0.0/0","selected":true}]').map(route => [route.id, route.ExitNode, route.Selected]),
  [['exit-1', true, true]],
  'netbird parses a JSON route array'
)
assertDeepEqual(
  netbird.parseRoutes('{"routes":[{"ID":"office","Network":"192.168.0.0/16","Status":"selected"}]}').map(route => route.id),
  ['office'],
  'netbird parses routes wrapped in an object'
)
assertDeepEqual(netbird.parseRoutes(''), [], 'netbird handles empty route output')
assertDeepEqual(netbird.parseRoutes('{'), [], 'netbird handles invalid route JSON')

assert(netbird.isExitNodeNetwork('0.0.0.0/0'), 'netbird treats the IPv4 default route as an exit node')
assert(netbird.isExitNodeNetwork('::/0'), 'netbird treats the IPv6 default route as an exit node')
assert(!netbird.isExitNodeNetwork('10.0.0.0/8'), 'netbird treats a private range as a plain route')

assertDeepEqual(
  netbird.sortRoutes(routesText).map(route => route.id),
  ['chicago-exit', 'internal-apps', 'office-lan'],
  'netbird sorts exit nodes ahead of plain routes'
)

const profiles = netbird.parseProfiles(JSON.stringify([
  { name: 'work', email: 'david@37signals.com', selected: true },
  { name: 'home', email: 'dhh@hey.com', selected: false }
]))
assertEqual(profiles.profiles.length, 2, 'netbird parses multiple profiles')
assertEqual(profiles.selectedProfileName, 'work', 'netbird records the selected profile')
assertEqual(profiles.selectedProfileLabel, 'work', 'netbird labels a profile by name')
assertEqual(
  netbird.profileLabel({ name: '', email: 'someone@example.com' }),
  'someone@example.com',
  'netbird labels a nameless profile by email'
)
assertDeepEqual(
  netbird.parseProfiles('{'),
  { profiles: [], selectedProfileName: '', selectedProfileLabel: '' },
  'netbird handles invalid profile JSON'
)

// Older CLIs have never heard of these subcommands, and that is not an error
// worth showing anybody.
assert(netbird.isUnsupportedCommand('Error: unknown command "profile" for "netbird"'), 'netbird recognizes an unknown subcommand')
assert(netbird.isUnsupportedCommand('unknown flag: --json'), 'netbird recognizes an unknown flag')
assert(!netbird.isUnsupportedCommand('failed to connect to daemon'), 'netbird does not mistake an outage for a missing command')

assert(netbird.isPermissionError('dial unix /var/run/netbird.sock: connect: permission denied'), 'netbird recognizes a socket it may not touch')
assert(netbird.isPermissionError('connection refused'), 'netbird recognizes a daemon that is not listening')
assert(!netbird.isPermissionError('peer is not logged in'), 'netbird does not mistake a logged-out daemon for an unreachable one')

// The admin panel URL is only in root-only daemon config, so the console is
// derived from the management URL that `netbird status --json` does report.
assertEqual(netbird.adminConsoleUrl('https://api.netbird.io:443'), 'https://app.netbird.io/peers', 'netbird sends the cloud management URL to the cloud console')
assertEqual(netbird.adminConsoleUrl('https://netbird.example.com:443'), 'https://netbird.example.com/peers', 'netbird derives a self-hosted console from its management URL')
assertEqual(netbird.adminConsoleUrl('https://nb.corp.net:33073'), 'https://nb.corp.net/peers', 'netbird drops a non-standard management port from the console URL')
assertEqual(netbird.adminConsoleUrl('http://nb.corp.net'), 'https://nb.corp.net/peers', 'netbird serves the console over https even when management is plain http')
assertEqual(netbird.adminConsoleUrl('nb.corp.net:443'), 'https://nb.corp.net/peers', 'netbird reads a management URL that carries no scheme')
assertEqual(netbird.adminConsoleUrl('https://[2001:db8::1]:443'), 'https://[2001:db8::1]/peers', 'netbird keeps an IPv6 literal bracketed')
assertEqual(netbird.adminConsoleUrl(''), 'https://app.netbird.io/peers', 'netbird falls back to the cloud console with no management URL')
assertEqual(netbird.adminConsoleUrl('https://api.netbird.io:443/some/path'), 'https://app.netbird.io/peers', 'netbird ignores a path on the management URL')
assert(/Model\.adminConsoleUrl\(managementUrl\)/.test(serviceSource), 'netbird opens the console it derived, not a hardcoded one')

// Go's zero time reaches the panel verbatim, in two spellings.
assert(netbird.isNeverTimestamp('0001-01-01T00:00:00Z'), 'netbird reads a zero handshake as never')
assert(netbird.isNeverTimestamp('0000-12-31T16:07:02-07:52'), 'netbird reads a zero status update in a local offset as never')
assert(netbird.isNeverTimestamp(''), 'netbird reads a missing timestamp as never')
assert(!netbird.isNeverTimestamp('2026-08-26T12:00:00Z'), 'netbird reads a real timestamp as a time')

assertEqual(netbird.formatBytes(0), '', 'netbird shows no traffic for a peer that moved none')
assertEqual(netbird.formatBytes(512), '512 B', 'netbird keeps bytes whole')
assertEqual(netbird.formatBytes(1536), '1.5 KB', 'netbird keeps one decimal under ten of a unit')
assertEqual(netbird.formatBytes(52428800), '50 MB', 'netbird drops the decimal past ten of a unit')

const NOW = Date.parse('2026-08-26T12:00:00Z')
assertEqual(netbird.relativeSince('2026-08-26T11:59:30Z', NOW), 'just now', 'netbird calls the last half minute just now')
assertEqual(netbird.relativeSince('2026-08-26T11:30:00Z', NOW), '30m ago', 'netbird counts back in minutes')
assertEqual(netbird.relativeSince('2026-08-26T09:00:00Z', NOW), '3h ago', 'netbird counts back in hours')
assertEqual(netbird.relativeSince('2026-08-24T12:00:00Z', NOW), '2d ago', 'netbird counts back in days')
assertEqual(netbird.relativeSince('0001-01-01T00:00:00Z', NOW), '', 'netbird reports no last-seen for a peer that never connected')

assertEqual(netbird.sessionExpiry('2026-08-27T10:00:00Z', NOW).text, 'Session expires in 22h', 'netbird counts a session down in hours')
assert(!netbird.sessionExpiry('2026-08-27T10:00:00Z', NOW).urgent, 'netbird leaves a session with hours left calm')
assertEqual(netbird.sessionExpiry('2026-08-26T12:38:00Z', NOW).text, 'Session expires in 38m', 'netbird counts the last hour down in minutes')
assert(netbird.sessionExpiry('2026-08-26T12:38:00Z', NOW).urgent, 'netbird marks the last hour of a session urgent')
assertEqual(netbird.sessionExpiry('2026-08-26T11:00:00Z', NOW).text, 'Session expired', 'netbird says so once the session has gone')
assert(netbird.sessionExpiry('2026-08-26T11:00:00Z', NOW).expired, 'netbird flags an expired session as expired')
assertEqual(netbird.sessionExpiry('', NOW).text, '', 'netbird stays quiet with no session expiry')

assertEqual(netbird.wireguardMode(true), 'kernel', 'netbird names the kernel WireGuard interface')
assertEqual(netbird.wireguardMode(false), 'userspace', 'netbird names the userspace WireGuard interface')

assertEqual(
  netbird.peerActivity({ TransferReceived: 5033165, TransferSent: 1258291, LastHandshake: '2026-08-26T09:00:00Z' }, NOW),
  '↓ 4.8 MB · ↑ 1.2 MB · last seen 3h ago',
  'netbird lines up a peer\'s traffic and last handshake'
)
assertEqual(
  netbird.peerActivity({ TransferReceived: 0, TransferSent: 0, LastHandshake: '0001-01-01T00:00:00Z' }, NOW),
  'never connected',
  'netbird says plainly when a peer has never connected'
)

const richStatus = netbird.parseStatus(JSON.stringify({
  daemonStatus: 'Connected',
  management: { url: 'https://fleetfold.com:443', connected: true },
  signal: { url: 'https://fleetfold.com:443', connected: true, error: '' },
  relays: { total: 2, available: 2 },
  usesKernelInterface: true,
  wireguardPort: 51820,
  sessionExpiresAt: '2026-08-27T12:25:37.510912187Z',
  peers: { total: 1, connected: 0, details: [
    { fqdn: 'proxy.netbird.selfhosted', netbirdIp: '100.122.124.134', status: 'Idle',
      transferSent: 10, transferReceived: 20, lastWireguardHandshake: '0001-01-01T00:00:00Z' }
  ] }
}))
assertEqual(richStatus.signalUrl, 'https://fleetfold.com:443', 'netbird reads the signal server URL')
assert(richStatus.signalConnected, 'netbird reads the signal connection')
assertEqual(richStatus.relaysAvailable + '/' + richStatus.relaysTotal, '2/2', 'netbird reads relay availability')
assertEqual(richStatus.wireguardMode, 'kernel', 'netbird reads the WireGuard interface mode from status')
assertEqual(richStatus.wireguardPort, 51820, 'netbird reads the WireGuard port')
assertEqual(richStatus.sessionExpiresAt, '2026-08-27T12:25:37.510912187Z', 'netbird carries the session expiry through')
assertEqual(richStatus.peers[0].TransferReceived, 20, 'netbird carries a peer\'s received bytes through')
assertEqual(richStatus.peers[0].TransferSent, 10, 'netbird carries a peer\'s sent bytes through')

assertEqual(netbird.urlHost('https://fleetfold.com:443'), 'fleetfold.com', 'netbird reads a host out of a management URL')
assertEqual(netbird.urlHost('https://[2001:db8::1]:443/x'), '[2001:db8::1]', 'netbird keeps an IPv6 host bracketed')
assertEqual(netbird.urlHost(''), '', 'netbird reads no host from an empty URL')

const health = netbird.healthRows({
  managementUrl: 'https://fleetfold.com:443', managementConnected: true,
  signalUrl: 'https://fleetfold.com:443', signalConnected: true,
  relaysAvailable: 2, relaysTotal: 2, wireguardMode: 'kernel', wireguardPort: 51820
})
assertEqual(health.map(r => r.label).join(','), 'Management,Signal,Relays,WireGuard', 'netbird lays out every health row')
assertEqual(health[0].value + ' ' + health[0].detail, 'fleetfold.com connected', 'netbird reports management by host and state')
assertEqual(health[2].value, '2/2', 'netbird reports relay availability as a fraction')
assertEqual(health[3].detail, 'port 51820', 'netbird reports the WireGuard port')
assert(!health.some(r => r.warn), 'netbird flags nothing on a healthy connection')

const degraded = netbird.healthRows({
  managementUrl: 'https://fleetfold.com:443', managementConnected: true,
  signalUrl: 'https://fleetfold.com:443', signalConnected: false,
  relaysAvailable: 0, relaysTotal: 2, wireguardMode: 'userspace', wireguardPort: 0
})
assert(degraded[1].warn, 'netbird flags a signal server that is not connected')
assert(degraded[2].warn, 'netbird flags a network with no relay available')
assert(!degraded[0].warn, 'netbird leaves reachable management unflagged while signal is down')
assertEqual(degraded[3].detail, '', 'netbird omits the WireGuard port when the daemon reports none')

// A relay-less deployment is a configuration, not a fault.
const norelays = netbird.healthRows({ relaysAvailable: 0, relaysTotal: 0 })
assert(!norelays[2].warn, 'netbird does not flag a deployment that configures no relays')
assertEqual(norelays[2].detail, 'none configured', 'netbird says when no relays are configured')
assertEqual(norelays.length, 3, 'netbird drops the WireGuard row when the mode is unknown')

assertDeepEqual(
  netbird.loginPlan(true, 'https://app.netbird.io/device?user_code=ABCD-EFGH'),
  { authUrl: 'https://app.netbird.io/device?user_code=ABCD-EFGH', command: [] },
  'netbird reuses a login URL the daemon already handed out'
)
assertDeepEqual(
  netbird.loginPlan(true, ''),
  { authUrl: '', command: ['netbird', 'up'] },
  'netbird runs up to request a login URL'
)
assertDeepEqual(
  netbird.loginPlan(false, 'https://app.netbird.io/device?user_code=STALE'),
  { authUrl: '', command: ['netbird', 'up'] },
  'netbird ignores a stale login URL outside the login state'
)

assertDeepEqual(
  netbird.parseStatus('{'),
  { ok: false, unavailable: true, message: 'Status error', error: 'Failed to parse netbird status' },
  'netbird reports invalid status JSON'
)
assertDeepEqual(
  netbird.parseStatus(''),
  { ok: true, unavailable: true, message: 'Disconnected' },
  'netbird treats empty status output as disconnected'
)
JS
