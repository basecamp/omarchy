#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const network = requireFromRoot('shell/plugins/panels/network/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/network/Panel.qml', 'utf8')

// parseVpnConnections: omarchy-network-vpn prints "name\tactive" lines.
assertDeepEqual(
  network.parseVpnConnections('pvpn-ch\tno\npvpn-fr\tyes\n'),
  [{ name: 'pvpn-ch', active: false }, { name: 'pvpn-fr', active: true }],
  'parseVpnConnections reads name/active pairs'
)

assertDeepEqual(network.parseVpnConnections(''), [], 'parseVpnConnections handles empty output')
assertDeepEqual(network.parseVpnConnections(undefined), [], 'parseVpnConnections handles undefined input')

// sortVpnConnections: active profile first, then alphabetical among the rest --
// mirrors sortWifiRows putting the connected network first.
assertDeepEqual(
  network.sortVpnConnections([
    { name: 'pvpn-fr', active: false },
    { name: 'pvpn-ch', active: true },
    { name: 'pvpn-de', active: false }
  ]),
  [
    { name: 'pvpn-ch', active: true },
    { name: 'pvpn-de', active: false },
    { name: 'pvpn-fr', active: false }
  ],
  'sortVpnConnections puts the active connection first, then sorts by name'
)

// Structural checks against Panel.qml, same style as network-test.sh: catch a
// wiring mistake (poll timer not gated, action not clearing busy state, list
// section still visible with nothing to show) without a running compositor.
assert(/property var vpnConnections: \[\]/.test(panelSource), 'network panel declares vpnConnections')
assert(/property string vpnActionName: ""/.test(panelSource), 'network panel declares vpnActionName')
assert(/property string vpnActionKind: ""/.test(panelSource), 'network panel declares vpnActionKind')
assert(/property string vpnFailureName: ""/.test(panelSource), 'network panel declares vpnFailureName')
assert(/property string vpnFailureReason: ""/.test(panelSource), 'network panel declares vpnFailureReason')

assert(/if \(!vpnProc\.running\) vpnProc\.running = true/.test(panelSource), 'refresh() kicks off the VPN listing')

const vpnPoll = panelSource.match(/Timer \{\n {4}id: vpnPoll[\s\S]*?\n {2}\}/)
assert(vpnPoll, 'network panel has a vpnPoll timer')
assert(/running: root\.opened/.test(vpnPoll[0]), 'vpnPoll only runs while the panel is open, like bandPoll')
assert(
  /running: root\.opened && root\.vpnConnections\.length > 0/.test(vpnPoll[0]),
  'vpnPoll does not shell out to nmcli every 4s on a machine with no VPN profiles'
)

const updateVpnConnections = panelSource.match(/function updateVpnConnections\(raw\) \{[\s\S]*?\n {2}\}/)
assert(updateVpnConnections, 'network panel has an updateVpnConnections function')
assert(
  /if \(vpnFailureName === "" \|\| vpnFailureReason !== "Connected, no traffic"\) return/.test(updateVpnConnections[0]),
  'updateVpnConnections only auto-clears the no-traffic warning, not a plain connect/disconnect failure'
)
assert(
  /if \(!stillActive\) vpnFailureName = ""/.test(updateVpnConnections[0]),
  'updateVpnConnections drops a failure once its connection is no longer active'
)

const vpnActionProc = panelSource.match(/Process \{\n {4}id: vpnActionProc[\s\S]*?\n {2}\}/)
assert(vpnActionProc, 'network panel has a vpnActionProc')
assert(/root\.vpnActionName = ""/.test(vpnActionProc[0]), 'vpnActionProc clears the busy row on exit')
assert(/root\.vpnActionKind = ""/.test(vpnActionProc[0]), 'vpnActionProc clears the pending action kind on exit')
assert(/exitCode === 0/.test(vpnActionProc[0]), 'vpnActionProc treats exit 0 as a plain success')
assert(
  /exitCode === 75\s*\n\s*\? "Connected, no traffic"/.test(vpnActionProc[0]),
  'vpnActionProc reads the private exit code 75 as a connected-but-no-traffic warning, not nmcli\'s own exit 2'
)
assert(
  /root\.vpnActionKind === "down" \? "Failed to disconnect" : "Failed to connect"/.test(vpnActionProc[0]),
  'vpnActionProc surfaces a plain nmcli failure distinctly from the no-traffic case'
)

const toggleVpn = panelSource.match(/function toggleVpn\(name, active\) \{[\s\S]*?\n {2}\}/)
assert(toggleVpn, 'network panel has a toggleVpn function')
assert(/vpnActionProc\.running/.test(toggleVpn[0]), 'toggleVpn guards against overlapping toggles')
assert(/vpnActionKind = active \? "down" : "up"/.test(toggleVpn[0]), 'toggleVpn records which direction it requested')

assert(/visible: root\.vpnConnections\.length > 0/.test(panelSource), 'VPN section is hidden when there are no profiles')

const vpnRow = panelSource.match(/component VpnRow: CursorSurface \{[\s\S]*?\n {2}\}/)
assert(vpnRow, 'network panel defines a VpnRow row component')
assert(/onClicked: root\.toggleVpn\(row\.conn\.name, row\.isActive\)/.test(vpnRow[0]), 'VpnRow click toggles the connection')
assert(/isFailed: !isBusy && root\.vpnFailureName/.test(vpnRow[0]), 'VpnRow only shows a failure once its own toggle has settled')
assert(/root\.vpnFailureReason/.test(vpnRow[0]), 'VpnRow renders the failure reason the panel recorded')

// Keyboard navigation: PanelKeyCatcher maps both arrow keys and j/k/h/l to
// the same onMoveRequested(dx, dy), so wiring the "vpn" section into that
// one handler covers both input styles at once -- nothing arrow-specific to
// test separately.
assert(/property int vpnIndex: -1/.test(panelSource), 'network panel declares vpnIndex')
assert(/"header" \| "band" \| "dns" \| "vpn" \| "wifi"/.test(panelSource), 'focusSection docs list vpn between dns and wifi')

const moveHandler = panelSource.match(/onMoveRequested: function\(dx, dy\) \{[\s\S]*?\n {6}\}\n {4}\}/)
assert(moveHandler, 'network panel has the onMoveRequested handler')
assert(
  /root\.focusSection === "dns"[\s\S]*?root\.vpnConnections\.length > 0\)[\s\S]*?root\.focusSection = "vpn"/.test(moveHandler[0]),
  'j from DNS enters the VPN section when it has profiles'
)
assert(
  /root\.focusSection === "vpn"[\s\S]*?dy < 0 && root\.vpnIndex <= 0[\s\S]*?root\.focusSection = "dns"/.test(moveHandler[0]),
  'k from the top VPN row escapes back to DNS'
)
assert(
  /root\.focusSection === "vpn"[\s\S]*?dy > 0 && root\.vpnIndex >= root\.vpnConnections\.length - 1[\s\S]*?root\.focusSection = "wifi"/.test(moveHandler[0]),
  'j from the bottom VPN row drops into wifi when there is somewhere to land'
)
assert(
  /root\.selectedIndex <= 0\)[\s\S]*?root\.vpnConnections\.length > 0\)[\s\S]*?root\.focusSection = "vpn"/.test(moveHandler[0]),
  'k from the top wifi row returns to VPN when it has profiles'
)

const activateHandler = panelSource.match(/onActivateRequested: \{[\s\S]*?\n {6}\}\n {4}\}/)
assert(activateHandler, 'network panel has the onActivateRequested handler')
assert(/root\.focusSection === "vpn"\) root\.activateVpn\(\)/.test(activateHandler[0]), 'Enter/Space on the VPN section activates the selected row')

const activateVpn = panelSource.match(/function activateVpn\(\) \{[\s\S]*?\n {2}\}/)
assert(activateVpn, 'network panel has an activateVpn function')
assert(/toggleVpn\(conn\.name, conn\.active\)/.test(activateVpn[0]), 'activateVpn toggles the row under the keyboard cursor')

assert(/isSelected: root\.focusSection === "vpn" && root\.vpnIndex === index/.test(vpnRow[0]), 'VpnRow tracks whether it is the keyboard-selected row')
assert(/hasCursor: root\.cursorActive && isSelected/.test(vpnRow[0]), 'VpnRow shows the keyboard cursor, not just mouse hover')
assert(
  /enabled: root\.vpnActionName === ""/.test(vpnRow[0]),
  'VpnRow locks every row while any VPN toggle is in flight, not just its own'
)

// The VPN list is a capped, scrollable ListView (like networkList below it),
// not an unbounded Column -- a long profile list must scroll instead of
// pushing DNS/wifi off the card.
const vpnListView = panelSource.match(/ListView \{\n {10}id: vpnList[\s\S]*?\n {8}\}/)
assert(vpnListView, 'network panel has a capped vpnList ListView')
assert(/height: Math\.min\(contentHeight, Style\.space\(240\)\)/.test(vpnListView[0]), 'vpnList caps its height like networkList')
assert(/clip: true/.test(vpnListView[0]), 'vpnList clips overflow instead of pushing later sections off the card')
assert(/currentIndex: root\.vpnIndex/.test(vpnListView[0]), 'vpnList follows the keyboard cursor')
assert(/positionViewAtIndex\(currentIndex, ListView\.Contain\)/.test(vpnListView[0]), 'vpnList scrolls the keyboard-selected row into view')

// A long connection name must not run under the status text on its right.
assert(/elide: Text\.ElideRight/.test(vpnRow[0]), 'VpnRow elides a name too long to fit')
assert(/anchors\.right: statusText\.left/.test(vpnRow[0]), 'VpnRow name is width-constrained against the status text, not free to overlap it')
JS

# The JS tests above only regex-match Panel.qml/omarchy-network-vpn source; they
# never exercise the shell script itself. These stub nmcli/ip/ping on PATH and
# run the real binary, covering exclusivity, rollback, and probe-failure
# mapping end to end.
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"
call_log="$tmp_dir/calls"

cat >"$mock_bin/nmcli" <<'STUB'
#!/bin/bash

printf 'nmcli %s\n' "$*" >>"$CALL_LOG"

if [[ $1 == "-e" && $2 == "no" && $3 == "-g" ]]; then
  field=$4
  obj=$5
  target=${7:-}

  if [[ $obj == "connection" && -z $target ]]; then
    printf '%s\n' "$CONN_LIST"
  elif [[ $field == "GENERAL.DEVICES" ]]; then
    [[ $target == "$VPN_NAME" ]] && printf '%s\n' "$VPN_DEVICE"
  elif [[ $field == "GENERAL.STATE" ]]; then
    [[ $target == "$VPN_DEVICE" ]] && printf '%s\n' "$VPN_STATE"
  fi
  exit 0
fi

if [[ $1 == "connection" && $2 == "up" ]]; then
  [[ $3 == "${NMCLI_UP_FAIL:-}" ]] && exit 1
  exit 0
fi

if [[ $1 == "connection" && $2 == "down" ]]; then
  [[ $3 == "${NMCLI_DOWN_FAIL:-}" ]] && exit 1
  exit 0
fi

exit 1
STUB

cat >"$mock_bin/ip" <<'STUB'
#!/bin/bash

printf 'ip %s\n' "$*" >>"$CALL_LOG"
[[ $6 == "$VPN_DEVICE" ]] && printf '%s\n' "$VPN_ROUTES"
exit 0
STUB

cat >"$mock_bin/ping" <<'STUB'
#!/bin/bash

printf 'ping %s\n' "$*" >>"$CALL_LOG"
exit "${PING_EXIT:-0}"
STUB

chmod +x "$mock_bin/nmcli" "$mock_bin/ip" "$mock_bin/ping"

export CALL_LOG="$call_log" VPN_NAME="" VPN_DEVICE="" VPN_STATE="" VPN_ROUTES="" \
  PING_EXIT=0 CONN_LIST="" NMCLI_UP_FAIL="" NMCLI_DOWN_FAIL=""

# $ROOT/bin so omarchy-network-vpn resolves the real omarchy-cmd-present.
vpn_run() {
  : >"$call_log"
  PATH="$mock_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-network-vpn" "$@"
}

logged_before() {
  local first="$1" second="$2" first_line second_line
  first_line=$(grep -Fxn -- "$first" "$call_log" | head -1 | cut -d: -f1)
  second_line=$(grep -Fxn -- "$second" "$call_log" | head -1 | cut -d: -f1)
  [[ -n $first_line && -n $second_line ]] || return 1
  (( first_line < second_line ))
}

# list_vpn_connections: bare invocation prints name/active pairs, dropping type.
CONN_LIST=$'pvpn-ch:wireguard:no\npvpn-fr:vpn:yes'
list_output=$(vpn_run) || fail "omarchy-network-vpn lists connections cleanly"
[[ $list_output == $'pvpn-ch\tno\npvpn-fr\tyes' ]] ||
  fail "omarchy-network-vpn lists profiles as name/active pairs" "$list_output"
pass "omarchy-network-vpn lists profiles as name/active pairs"

# up: exclusivity deactivates the other active profile before activating the
# requested one. Split-tunnel routes skip the traffic probe outright.
CONN_LIST=$'pvpn-ch:wireguard:yes\npvpn-fr:wireguard:no'
VPN_NAME=pvpn-fr VPN_DEVICE=wg1 VPN_STATE="100 (connected)" VPN_ROUTES="10.0.0.0/24 dev wg1 scope link"
vpn_run up pvpn-fr || fail "omarchy-network-vpn activates a verified split-tunnel profile"
pass "omarchy-network-vpn activates a verified split-tunnel profile"
logged_before "nmcli connection down pvpn-ch" "nmcli connection up pvpn-fr" ||
  fail "omarchy-network-vpn deactivates the other active profile before activating the requested one" "$(cat "$call_log")"
pass "omarchy-network-vpn deactivates the other active profile before activating the requested one"

# up: a full tunnel that fails the traffic probe reports the dedicated exit
# code and warning, without touching exclusivity.
CONN_LIST=$'pvpn-de:wireguard:no'
VPN_NAME=pvpn-de VPN_DEVICE=wg2 VPN_STATE="100 (connected)" VPN_ROUTES="default via 10.0.0.1 dev wg2"
PING_EXIT=1
if err=$(vpn_run up pvpn-de 2>&1 >/dev/null); then status=0; else status=$?; fi
(( status == 75 )) || fail "omarchy-network-vpn reports the no-traffic exit code" "exit status: $status"
pass "omarchy-network-vpn reports the no-traffic exit code"
[[ $err == *"Warning: pvpn-de connected but is not passing traffic."* ]] ||
  fail "omarchy-network-vpn warns when a full tunnel carries no traffic" "$err"
pass "omarchy-network-vpn warns when a full tunnel carries no traffic"

# up: the same full tunnel succeeds outright once the probe passes.
PING_EXIT=0
vpn_run up pvpn-de || fail "omarchy-network-vpn accepts a full tunnel that passes traffic"
pass "omarchy-network-vpn accepts a full tunnel that passes traffic"

# up: a profile that fails to activate outright rolls back to whatever was
# active before, instead of leaving nothing connected.
CONN_LIST=$'pvpn-ch:wireguard:yes\npvpn-fr:wireguard:no'
NMCLI_UP_FAIL=pvpn-fr
if err=$(vpn_run up pvpn-fr 2>&1 >/dev/null); then status=0; else status=$?; fi
(( status == 1 )) || fail "omarchy-network-vpn fails when activation is refused outright" "exit status: $status"
pass "omarchy-network-vpn fails when activation is refused outright"
[[ $err == *"Error: failed to activate pvpn-fr."* ]] ||
  fail "omarchy-network-vpn reports the activation failure" "$err"
pass "omarchy-network-vpn reports the activation failure"
grep -Fxq "nmcli connection up pvpn-ch" "$call_log" ||
  fail "omarchy-network-vpn rolls back to the previously active profile" "$(cat "$call_log")"
pass "omarchy-network-vpn rolls back to the previously active profile"
NMCLI_UP_FAIL=""

# down: a refused deactivation is reported, not silently swallowed.
NMCLI_DOWN_FAIL=pvpn-ch
if err=$(vpn_run down pvpn-ch 2>&1 >/dev/null); then status=0; else status=$?; fi
(( status == 1 )) || fail "omarchy-network-vpn fails when deactivation is refused" "exit status: $status"
pass "omarchy-network-vpn fails when deactivation is refused"
[[ $err == *"Error: failed to deactivate pvpn-ch."* ]] ||
  fail "omarchy-network-vpn reports the deactivation failure" "$err"
pass "omarchy-network-vpn reports the deactivation failure"
NMCLI_DOWN_FAIL=""

# up: deactivate_other_vpns compares the activating profile's name literally,
# not as a glob pattern -- a name with a glob metacharacter must not make an
# unrelated active profile with a matching prefix look like a self-match and
# get skipped, breaking exclusivity.
CONN_LIST=$'work*:wireguard:no\nworkstation:wireguard:yes'
VPN_NAME='work*' VPN_DEVICE=wg3 VPN_STATE="100 (connected)" VPN_ROUTES="10.0.0.0/24 dev wg3"
vpn_run up 'work*' || fail "omarchy-network-vpn activates a profile whose name contains a glob metacharacter"
pass "omarchy-network-vpn activates a profile whose name contains a glob metacharacter"
grep -Fxq "nmcli connection down workstation" "$call_log" ||
  fail "omarchy-network-vpn deactivates an unrelated profile instead of glob-matching it against the activating name" "$(cat "$call_log")"
pass "omarchy-network-vpn deactivates an unrelated profile instead of glob-matching it against the activating name"
