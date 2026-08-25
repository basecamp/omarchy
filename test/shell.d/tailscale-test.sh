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
// Tailscale names a profile after its login unless one is set explicitly, so
// the nickname is never empty and would otherwise hide the display name the
// admin console set.
assertEqual(
  tailscale.accountLabel({ nickname: 'user@example', tailnet: 'Acme Corp', account: 'user@example', id: 'abcd' }),
  'Acme Corp',
  'tailscale labels connections by tailnet display name when the profile only carries its login'
)
assertEqual(
  tailscale.accountLabel({ nickname: 'Work', tailnet: 'Acme Corp', account: 'user@example', id: 'abcd' }),
  'Work',
  'tailscale prefers a deliberately set nickname over the tailnet display name'
)
assertEqual(
  tailscale.accountLabel({ nickname: 'user@example', tailnet: '', account: 'user@example', id: 'abcd' }),
  'user@example',
  'tailscale falls back to the login when no display name is available'
)
assertEqual(
  tailscale.accountLabel({ nickname: '', tailnet: '', account: '', id: 'abcd' }),
  'abcd',
  'tailscale falls back to the profile id'
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

assert(/addArmed = false\s*\n\s*tailscale\.addAccount\(\)/.test(panelSource), 'tailscale activates the add row as a login rather than a switch')
assert(/var command = \["tailscale", "login", "--accept-routes"\]/.test(serviceSource), 'tailscale adds a connection the way the service install brings one up')
// A fresh profile without an operator answers even `tailscale switch` with
// access denied, so an abandoned login would lock the way back behind sudo.
assert(/command\.push\("--operator=" \+ userName\)/.test(serviceSource), 'tailscale keeps operator access on the profile it creates')
// tailscale login makes the new profile current before the browser half
// finishes, so an abandoned login must not leave the machine stranded on it.
assert(/_addAccountPreviousId = selectedAccountId/.test(serviceSource), 'tailscale remembers the connection it is leaving')
assert(/root\.returnToPreviousAccount\(\)/.test(serviceSource), 'tailscale goes back when the login does not land')
// The accounts list is only re-read once a minute, so at the moment the login
// fails selectedAccountId still names the profile being returned to. Comparing
// against it there skips the one switch that matters.
assert(!/if \(previous === "" \|\| previous === selectedAccountId/.test(serviceSource), 'tailscale does not skip the return on a stale selected account')

// The whole point of the recovery is what happens on each way this can end, so
// the decision is a plain function rather than something only a real second
// tailnet could exercise.
assertDeepEqual(
  tailscale.addAccountOutcome(0, true, 'db1b', ''),
  { returnTo: '', status: '', error: '' },
  'tailscale stays put when the login lands'
)
assertDeepEqual(
  tailscale.addAccountOutcome(1, true, 'db1b', ''),
  { returnTo: 'db1b', status: 'Login not completed — back on the previous connection', error: '' },
  'tailscale returns to the previous connection when the login is abandoned'
)
assertDeepEqual(
  tailscale.addAccountOutcome(1, false, 'db1b', 'access denied'),
  { returnTo: 'db1b', status: 'access denied', error: 'access denied' },
  'tailscale reports a login that failed before it reached the browser'
)
assertDeepEqual(
  tailscale.addAccountOutcome(1, false, 'db1b', '   '),
  { returnTo: 'db1b', status: 'tailscale login failed', error: 'tailscale login failed' },
  'tailscale still says something when the login fails silently'
)
assertDeepEqual(
  tailscale.addAccountOutcome(1, true, '', ''),
  { returnTo: '', status: 'Login not completed — back on the previous connection', error: '' },
  'tailscale has nowhere to return when there was no previous connection'
)
// A cancel kills the process, which exits non-zero like any other failure.
assertDeepEqual(
  tailscale.addAccountOutcome(143, true, 'db1b', ''),
  { returnTo: 'db1b', status: 'Login not completed — back on the previous connection', error: '' },
  'tailscale returns to the previous connection when the login is cancelled'
)

assert(/Back on your connection — sign in again to reconnect/.test(serviceSource), 'tailscale says the returned connection needs signing in again')
assert(/function cancelAddAccount\(\) \{[\s\S]*?addAccountProcess\.running = false[\s\S]*?returnToPreviousAccount\(\)/.test(serviceSource), 'tailscale can bail out of a login in progress')
assert(/if \(accountRow\.addingAccount\) tailscale\.cancelAddAccount\(\)/.test(panelSource), 'tailscale offers the bail-out on the row that is running')
assert(/if \(!addArmed\) \{\s*\n\s*addArmed = true/.test(panelSource), 'tailscale asks before signing the machine out to add a tailnet')
assert(/readonly property bool addingAccount: addAccountProcess\.running/.test(serviceSource), 'tailscale publishes that a connection is being added')
assert(/running: accountRow\.working/.test(panelSource), 'tailscale animates the row while it is adding or switching')
assert(/if \(addingAccount\) return "Opening browser…"/.test(panelSource), 'tailscale says what the add row is doing while it runs')
assert(/"Signs out of " \+ current \+ " — confirm\?"/.test(panelSource), 'tailscale says which connection adding will sign out of')

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

// The login hand-off keys off _loginInProgress, so standing down on the first
// missed interval left the panel holding a URL it would never open, behind a
// message that never cleared.
assert(/if \(attempts < 3\) \{/.test(serviceSource), 'tailscale waits more than one interval for the login link')
assert(/attempts \+= 1/.test(serviceSource), 'tailscale counts its attempts at the login link')
assert(/root\.actionStatus = "Tailscale login link not available yet"\s*\n(\s*\/\/[^\n]*\n)*\s*actionStatusTimer\.restart\(\)/.test(serviceSource), 'tailscale clears the login link message instead of freezing on it')
assert(/loginTimeoutTimer\.attempts = 0/.test(serviceSource), 'tailscale starts each login with a fresh attempt count')
// pkexec exits 126 when the dialog is dismissed, which is a decision rather
// than a failure and should not be reported as one.
assert(/if \(exitCode === 126\) \{\s*\n\s*root\.lastError = ""\s*\n\s*root\.actionStatus = ""/.test(serviceSource), 'tailscale leaves nothing behind when the operator prompt is dismissed')
assert(/\} else if \(exitCode !== 0\) \{\s*\n\s*root\.lastError = elideStatus\(stderr \|\| stdout \|\| "Tailscale authorization failed"\)/.test(serviceSource), 'tailscale still reports a real authorization failure')
// Exactly what the panel showed on a machine whose client and daemon differ:
// the warning arrives on stderr ahead of the real refusal.
assertEqual(
  tailscale.commandMessage('Warning: client version "1.102.3" != tailscaled server version "1.102.2"\nAccess denied: checkprefs access denied\nUse \'sudo tailscale up\'.'),
  "Access denied: checkprefs access denied Use 'sudo tailscale up'.",
  'tailscale drops the version skew warning from what it shows'
)
assertEqual(
  tailscale.commandMessage('Warning: client version "1.2" != tailscaled server version "1.1"'),
  '',
  'tailscale is left with nothing when the warning was the whole of it'
)
assertEqual(tailscale.commandMessage('  boom  \n\n  bang \n'), 'boom bang', 'tailscale joins what is left onto one line')
assertEqual(tailscale.commandMessage(''), '', 'tailscale handles empty command output')
assertEqual(tailscale.commandMessage(null), '', 'tailscale handles missing command output')

assert(tailscale.isAccessDenied('Access denied: checkprefs access denied'), 'tailscale spots a refusal for want of the operator')
// tailscale login --operator is refused by the very check it would fix, so the
// add row can only dead-end while the panel already knows it lacks the operator.
assertDeepEqual(tailscale.connectionRows([{ id: 'db1b' }], false).map(row => row.id), ['db1b'], 'tailscale withholds the add row when it cannot be used')
assert(/tailscale\.active && !tailscale\.accountsAccessDenied/.test(panelSource), 'tailscale hides the add row while it lacks the operator')
assert(/if \(Model\.isAccessDenied\(outcome\.error\)\) \{\s*\n\s*root\.reportCommandError/.test(serviceSource), 'tailscale offers the operator fix when the add is refused')
assert(tailscale.isAccessDenied('profiles access denied'), 'tailscale spots the profiles refusal too')
assert(!tailscale.isAccessDenied('tailscale up failed'), 'tailscale does not mistake an ordinary failure for a refusal')

// A refusal has a fix the panel can offer, so it raises that instead of
// repeating the CLI's advice to go and use sudo.
assert(/accountsAccessDenied = true\s*\n\s*message = "Tailscale needs permission on this machine"/.test(serviceSource), 'tailscale offers the operator fix when a command is refused')
assert(/root\.reportCommandError\(combined, "tailscale up failed"\)/.test(serviceSource), 'tailscale reports a failed connect through the same path')

assertDeepEqual(tailscale.parseStatus('{'), { ok: false, unavailable: true, message: 'Status error', error: 'Failed to parse tailscale status' }, 'tailscale reports invalid status JSON')
assertDeepEqual(tailscale.parseAccounts('{'), { accounts: [], selectedAccountId: '', selectedAccountLabel: '' }, 'tailscale handles invalid account JSON')
JS
