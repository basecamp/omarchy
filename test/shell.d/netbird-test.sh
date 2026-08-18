#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const netbird = requireFromRoot('shell/plugins/panels/netbird/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/netbird/Panel.qml', 'utf8')

assert(/function toggleNetbird\(\): string \{ netbird\.toggleNetbird\(\); return "ok" \}/.test(panelSource), 'netbird exposes the connection toggle over IPC')

assertEqual(netbird.parseNetbirdIp('100.64.0.1/32'), '100.64.0.1', 'netbird strips CIDR suffix from IP')
assertEqual(netbird.parseNetbirdIp('100.64.0.1'), '100.64.0.1', 'netbird keeps IP without CIDR')
assertEqual(netbird.parseNetbirdIp(''), '', 'netbird handles empty IP')

assertEqual(netbird.shortName('mbp-hq2l7694pv.netbird.cloud'), 'mbp-hq2l7694pv', 'netbird extracts short name from FQDN')
assertEqual(netbird.shortName('mbp-hq2l7694pv.netbird.cloud.'), 'mbp-hq2l7694pv', 'netbird handles trailing dot in FQDN')
assertEqual(netbird.shortName('hostname'), 'hostname', 'netbird handles bare hostname')
assertEqual(netbird.shortName(''), '', 'netbird handles empty FQDN')

const status = netbird.parseStatus(JSON.stringify({
  daemonStatus: 'Connected',
  fqdn: 'johwork01-75-54.netbird.cloud',
  netbirdIp: '100.111.75.54/16',
  profileName: 'default',
  management: { url: 'https://api.netbird.io:443', connected: true, error: '' },
  peers: {
    total: 3,
    connected: 1,
    details: [
      {
        fqdn: 'alpha.netbird.cloud',
        netbirdIp: '100.111.1.1/32',
        status: 'Connected',
        connectionType: 'P2P',
        latency: 5000,
        networks: ['10.100.0.0/16']
      },
      {
        fqdn: 'beta.netbird.cloud',
        netbirdIp: '100.111.2.2/32',
        status: 'Idle',
        connectionType: '-',
        latency: 0,
        networks: null
      },
      {
        fqdn: 'gamma.netbird.cloud',
        netbirdIp: '100.111.3.3',
        status: 'Connecting',
        connectionType: '-',
        latency: 23000000,
        networks: null
      }
    ]
  }
}))

assert(status.ok && status.running, 'netbird parses connected status')
assertEqual(status.selfName, 'johwork01-75-54', 'netbird parses self name from FQDN')
assertEqual(status.selfIp, '100.111.75.54', 'netbird parses self IP without CIDR')
assertEqual(status.profileName, 'default', 'netbird parses profile name')
assert(status.managementConnected, 'netbird parses management connection state')

assertEqual(status.peers.length, 3, 'netbird includes all peers')
assertDeepEqual(
  status.peers.map(peer => peer.HostName),
  ['alpha', 'gamma', 'beta'],
  'netbird sorts peers by status (Connected, Connecting, Idle) then alphabetically'
)
assertEqual(status.peers[0].NetbirdIP, '100.111.1.1', 'netbird parses peer IP with CIDR suffix stripped')
assertEqual(status.peers[0].Status, 'Connected', 'netbird preserves peer status')
assertEqual(status.peers[0].ConnectionType, 'P2P', 'netbird preserves connection type')
assert(status.peers[0].Online, 'netbird marks connected peers as online')
assert(status.peers[1].Online, 'netbird marks connecting peers as online')
assert(!status.peers[2].Online, 'netbird marks idle peers as offline')

const stopped = netbird.parseStatus(JSON.stringify({
  daemonStatus: 'Disconnected',
  fqdn: 'host.netbird.cloud',
  netbirdIp: '',
  peers: { total: 0, connected: 0, details: [] }
}))

assert(stopped.ok && !stopped.running, 'netbird parses disconnected status')

const profiles = netbird.parseProfiles(`Found 2 profiles:
✓ default
  work`)

assertEqual(profiles.profiles.length, 2, 'netbird parses multiple profiles')
assertEqual(profiles.selectedProfileId, 'default', 'netbird records selected profile')
assertDeepEqual(
  profiles.profiles.map(profile => profile.name),
  ['default', 'work'],
  'netbird preserves profile names'
)
assert(profiles.profiles[0].selected, 'netbird marks selected profile')
assert(!profiles.profiles[1].selected, 'netbird does not mark unselected profile')

const singleProfile = netbird.parseProfiles(`Found 1 profiles:
✓ default`)

assertEqual(singleProfile.profiles.length, 1, 'netbird parses single profile')
assertEqual(singleProfile.selectedProfileId, 'default', 'netbird records single selected profile')

assertDeepEqual(netbird.parseStatus('{'), { ok: false, unavailable: true, message: 'Status error', error: 'Failed to parse netbird status' }, 'netbird reports invalid status JSON')
assertDeepEqual(netbird.parseProfiles(''), { profiles: [], selectedProfileId: '', selectedProfileLabel: '' }, 'netbird handles empty profile output')
JS