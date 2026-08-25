#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const tailscale = requireFromRoot('shell/plugins/panels/tailscale/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/tailscale/Panel.qml', 'utf8')
const serviceSource = fs.readFileSync(root + '/shell/plugins/panels/tailscale/Service.qml', 'utf8')

assert(/function toggleTailscale\(\): string \{ tailscale\.toggleTailscale\(\); return "ok" \}/.test(panelSource), 'tailscale exposes the connection toggle over IPC')

assertDeepEqual(
  tailscale.filterIPv4(['100.64.0.1', 'fd7a:115c:a1e0::1', '192.168.1.2']),
  ['100.64.0.1'],
  'tailscale keeps only Tailscale IPv4 addresses'
)
assertDeepEqual(
  tailscale.filterIPv6(['100.64.0.1', 'fd7a:115c:a1e0::1', 'fe80::1']),
  ['fd7a:115c:a1e0::1'],
  'tailscale keeps only Tailscale IPv6 addresses'
)

assertEqual(tailscale.cleanDnsName('work.tailnet.ts.net.'), 'work.tailnet.ts.net', 'tailscale strips trailing DNS dot')
assertEqual(tailscale.displayHostName('localhost', 'work.tailnet.ts.net.'), 'work', 'tailscale falls back from localhost to short DNS name')

const status = tailscale.parseStatus(JSON.stringify({
  BackendState: 'Running',
  AuthURL: '',
  TailscaleIPs: ['100.74.97.73', 'fd7a:115c:a1e0::ff32:6149'],
  Self: {
    HostName: 'dhh-fd',
    DNSName: 'dhh-fd.tail32f559.ts.net.',
    TailscaleIPs: ['100.74.97.73'],
    UserID: 1001,
    CapMap: { 'https://tailscale.com/cap/file-sharing': null }
  },
  Peer: {
    onlineB: {
      HostName: 'zed',
      DNSName: 'zed.tail32f559.ts.net.',
      TailscaleIPs: ['100.1.1.2'],
      Online: true,
      OS: 'linux',
      ExitNodeOption: true,
      ExitNode: true,
      UserID: 1002,
      TaildropTarget: 5
    },
    offline: {
      HostName: 'offline',
      DNSName: 'offline.tail32f559.ts.net.',
      TailscaleIPs: ['100.1.1.3'],
      Online: false,
      OS: 'linux'
    },
    offlineExit: {
      HostName: 'mbu-ser9',
      DNSName: 'mbu-ser9.tail32f559.ts.net.',
      TailscaleIPs: ['100.125.28.77', 'fd7a:115c:a1e0::1037:1c4d'],
      Online: false,
      OS: 'linux',
      ExitNodeOption: true,
      ExitNode: false
    },
    onlineA: {
      HostName: 'alpha',
      DNSName: 'alpha.tail32f559.ts.net.',
      TailscaleIPs: ['100.1.1.1', 'fd7a:115c:a1e0::1901:334b'],
      Online: true,
      OS: 'macos',
      UserID: 1001,
      TaildropTarget: 1
    },
    mullvadExit: {
      HostName: 'al-tia-wg-003',
      DNSName: 'al-tia-wg-003.mullvad.ts.net.',
      TailscaleIPs: ['100.95.87.11'],
      Online: true,
      OS: 'linux',
      ExitNodeOption: true,
      ExitNode: false
    }
  }
}))

assert(status.ok && status.running, 'tailscale parses running status')
assertEqual(status.selfIp, '100.74.97.73', 'tailscale parses self IP')
assertDeepEqual(status.peers.map(peer => peer.HostName), ['alpha', 'zed'], 'tailscale filters offline and Mullvad peers and sorts online peers')
assertDeepEqual(status.peers[0].TailscaleIPv6, ['fd7a:115c:a1e0::1901:334b'], 'tailscale preserves peer IPv6 addresses for copy menu')
assert(status.peers[1].ExitNodeOption && status.peers[1].ExitNode, 'tailscale preserves exit node flags')
assertDeepEqual(status.exitNodes.map(peer => peer.HostName), ['zed'], 'tailscale lists only online tailnet exit nodes')
assert(tailscale.isMullvadPeer({ HostName: 'al-tia-wg-003', DNSName: 'al-tia-wg-003.mullvad.ts.net.' }), 'tailscale detects Mullvad status peers')

assert(status.fileSharing, 'tailscale reads Taildrop capability from the status capability map')
assertEqual(status.selfUserId, '1001', 'tailscale records the owning user of this machine')
assertDeepEqual(status.peers.map(peer => peer.UserID), ['1001', '1002'], 'tailscale records the owning user of each peer')
assert(
  tailscale.hasFileSharing({ Capabilities: ['https://tailscale.com/cap/file-sharing'] }),
  'tailscale reads Taildrop capability from the legacy capability list'
)
assert(!tailscale.hasFileSharing({ CapMap: { funnel: null } }), 'tailscale reports no Taildrop without the capability')
assertDeepEqual(status.peers.map(peer => peer.TaildropTarget), [1, 5], 'tailscale records how Tailscale grades each Taildrop target')
assert(tailscale.isTaildropTarget({ TaildropTarget: 1, UserID: '1001' }, '2002'), 'tailscale trusts an available Taildrop target')
assert(!tailscale.isTaildropTarget({ TaildropTarget: 7, UserID: '1001' }, '1001'), 'tailscale skips peers Tailscale rules out')
assert(tailscale.isTaildropTarget({ UserID: '1001' }, '1001'), 'tailscale falls back to same-owner peers without a grade')
assert(!tailscale.isTaildropTarget({ UserID: '1002' }, '1001'), 'tailscale skips other owners without a grade')

const mullvadNodes = tailscale.parseExitNodeList(`
 IP                  HOSTNAME                         COUNTRY            CITY                   STATUS
 100.65.216.13       au-adl-wg-301.mullvad.ts.net     Australia          Any                    -
 100.65.216.13       au-adl-wg-301.mullvad.ts.net     Australia          Adelaide               -
 100.70.240.117      au-bne-wg-301.mullvad.ts.net     Australia          Brisbane               -
 100.66.11.119       dk-cph-wg-001.mullvad.ts.net     Denmark            Copenhagen             -
 100.101.10.10       us-chi-wg-001.mullvad.ts.net     United States      Chicago                -
 100.102.10.10       us-nyc-wg-001.mullvad.ts.net     United States      New York               -
 100.1.2.3           office.tailnet.ts.net             Denmark            Office                 -

# To use an exit node, use tailscale set --exit-node=
`)

assertDeepEqual(
  mullvadNodes.map(node => node.DisplayName),
  ['Adelaide, Australia', 'Brisbane, Australia', 'Copenhagen, Denmark', 'Chicago, United States', 'New York, United States'],
  'tailscale parses Mullvad exit nodes and skips duplicate country rows'
)
assertEqual(mullvadNodes[2].DNSName, 'dk-cph-wg-001.mullvad.ts.net', 'tailscale preserves Mullvad hostname as exit node target')
assertDeepEqual(mullvadNodes[2].TailscaleIPs, ['100.66.11.119'], 'tailscale preserves Mullvad exit node IP')
assert(mullvadNodes.every(node => node.Mullvad === true && node.ExitNodeOption === true), 'tailscale marks Mullvad rows as exit nodes')

const mullvadRegions = tailscale.mullvadRegionOptions(mullvadNodes)
assertDeepEqual(
  mullvadRegions.map(node => node.DisplayName),
  ['Adelaide, Australia', 'Brisbane, Australia', 'Copenhagen, Denmark', 'Chicago, United States', 'New York, United States'],
  'tailscale groups Mullvad exit nodes by unique city region'
)
assertDeepEqual(
  mullvadRegions.filter(node => node.Country === 'United States').map(node => node.City),
  ['Chicago', 'New York'],
  'tailscale keeps multiple Mullvad cities within a country'
)
assertEqual(mullvadRegions[0].DNSName, 'au-adl-wg-301.mullvad.ts.net', 'tailscale uses a concrete city endpoint for grouped regions')
assertEqual(mullvadRegions[2].DNSName, 'dk-cph-wg-001.mullvad.ts.net', 'tailscale preserves first available city endpoint')

const stopped = tailscale.parseStatus(JSON.stringify({
  BackendState: 'Stopped',
  Peer: {
    online: {
      HostName: 'alpha',
      DNSName: 'alpha.tail32f559.ts.net.',
      TailscaleIPs: ['100.1.1.1'],
      Online: true,
      OS: 'macos'
    }
  }
}))

assert(stopped.ok && !stopped.running, 'tailscale parses stopped status')

const accounts = tailscale.parseAccounts(JSON.stringify([
  {
    id: 'db1b',
    nickname: 'Home',
    tailnet: 'dhh.github',
    account: 'dhh@github',
    selected: true
  },
  {
    id: '1785',
    nickname: 'Work',
    tailnet: '37signals.com',
    account: 'david@37signals.com',
    selected: false
  }
]))

assertEqual(accounts.accounts.length, 2, 'tailscale parses multiple connections')
assertEqual(accounts.selectedAccountId, 'db1b', 'tailscale records selected connection id')
assertEqual(accounts.selectedAccountLabel, 'Home', 'tailscale labels connections by nickname')
assertDeepEqual(
  accounts.accounts.map(account => account.nickname),
  ['Home', 'Work'],
  'tailscale preserves connection nicknames'
)
assertEqual(
  tailscale.accountLabel({ nickname: '', tailnet: 'tailnet.example', account: 'user@example', id: 'abcd' }),
  'tailnet.example',
  'tailscale labels connections by tailnet when nickname is missing'
)

assertDeepEqual(
  tailscale.connectionRows(accounts.accounts, true).map(row => row.id),
  ['db1b', '1785', 'account:add'],
  'tailscale offers adding a tailnet after the existing connections'
)
assertDeepEqual(
  tailscale.connectionRows([{ id: 'db1b', nickname: 'Home', selected: true }], true).map(row => row.id),
  ['db1b', 'account:add'],
  'tailscale offers adding a tailnet when only one connection exists'
)
assertDeepEqual(
  tailscale.connectionRows(accounts.accounts, false).map(row => row.id),
  ['db1b', '1785'],
  'tailscale withholds the add row while disconnected'
)
assertDeepEqual(tailscale.connectionRows(null, true).map(row => row.id), ['account:add'], 'tailscale handles a missing connection list')

assert(/if \(account\.AddAccount === true\) \{\s*\n\s*disarmRemoval\(\)\s*\n\s*tailscale\.addAccount\(\)/.test(panelSource), 'tailscale activates the add row as a login rather than a switch')
assert(/addAccountProcess\.command = \["tailscale", "login", "--accept-routes"\]/.test(serviceSource), 'tailscale adds a connection the way the service install brings one up')
assert(/readonly property bool addingAccount: addAccountProcess\.running/.test(serviceSource), 'tailscale publishes that a connection is being added')
assert(/running: accountRow\.working/.test(panelSource), 'tailscale animates the row while it is adding or switching')
assert(/addingAccount \? "Opening browser…" : "Add account…"/.test(panelSource), 'tailscale says what the add row is doing while it runs')

assert(/removeProcess\.command = \["tailscale", "switch", "remove", accountId\]/.test(serviceSource), 'tailscale removes a connection from this machine')
// Removing the profile in use would strand the machine mid-session.
assert(/if \(accountId === selectedAccountId\) return/.test(serviceSource), 'tailscale refuses to remove the connection in use')
assert(/account\.selected !== true && String\(account\.id \|\| ""\) !== ""/.test(panelSource), 'tailscale offers removal only on connections that are not in use')
// Two deliberate activations, so a stray click cannot drop a connection.
assert(/if \(removeArmedId === String\(account\.id \|\| ""\)\) \{\s*\n\s*confirmRemoval\(account\)/.test(panelSource), 'tailscale takes a second activation to confirm a removal')
assert(/armed \? "Remove " \+ label \+ "\?"/.test(panelSource) || /if \(armed\) return "Remove " \+ label \+ "\?"/.test(panelSource), 'tailscale asks before removing')
assert(/onCloseRequested: \{\s*\n\s*if \(root\.removeArmedId !== ""\) root\.disarmRemoval\(\)/.test(panelSource), 'tailscale backs out of the question before closing the panel')
assert(/disarmRemoval\(\)\s*\n\s*ensureCursor\(\)/.test(panelSource), 'tailscale abandons the question when the cursor moves off the row')
// The toggle's login hand-off keys off _loginInProgress, which a status poll
// clears as soon as tailscaled is running — the state adding an account starts
// from. Sharing that process would drop the auth URL.
assert(/Process \{\s*\n\s*id: addAccountProcess/.test(serviceSource), 'tailscale adds a connection on its own process, not the toggle\'s')

assertDeepEqual(
  tailscale.loginPlan(true, 'https://login.tailscale.com/a/existing'),
  { authUrl: 'https://login.tailscale.com/a/existing', command: [] },
  'tailscale reuses the daemon authorization URL without replacing node identity'
)
assertDeepEqual(
  tailscale.loginPlan(true, ''),
  { authUrl: '', command: ['tailscale', 'up'] },
  'tailscale requests a login URL when the daemon has not supplied one'
)
assertDeepEqual(
  tailscale.loginPlan(false, 'https://login.tailscale.com/a/stale'),
  { authUrl: '', command: ['tailscale', 'up'] },
  'tailscale ignores stale authorization URLs outside the login state'
)

assertDeepEqual(tailscale.parseStatus('{'), { ok: false, unavailable: true, message: 'Status error', error: 'Failed to parse tailscale status' }, 'tailscale reports invalid status JSON')
assertDeepEqual(tailscale.parseAccounts('{'), { accounts: [], selectedAccountId: '', selectedAccountLabel: '' }, 'tailscale handles invalid account JSON')
JS
