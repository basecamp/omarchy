#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

dns="$ROOT/bin/omarchy-dns"
hardware_network="$ROOT/install/hardware/network.sh"
migration="$ROOT/migrations/1782002156.sh"

! grep -F 'systemd-networkd' "$dns" >/dev/null || fail "omarchy-dns no longer restarts systemd-networkd"
grep -F 'NetworkManager/conf.d/20-omarchy-dns.conf' "$dns" >/dev/null
grep -F '[global-dns-domain-*]' "$dns" >/dev/null
! grep -F 'ipv4.ignore-auto-dns yes' "$dns" >/dev/null || fail "provider changes no longer rewrite connection DNS"
grep -F 'ipv4.ignore-auto-dns no' "$dns" >/dev/null
grep -F 'connection_uses_dhcp_dns' "$dns" >/dev/null
grep -F 'nmcli device reapply' "$dns" >/dev/null
grep -F 'nmcli general reload conf' "$dns" >/dev/null
grep -F 'nmcli general reload dns-full' "$dns" >/dev/null
if grep -F 'nmcli general reload conf,dns-full' "$dns" >/dev/null; then
  fail "omarchy-dns must not push DNS before reapplying active profiles"
fi
pass "omarchy-dns configures DNS through NetworkManager"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export DNS_CALLS="$test_tmp/calls"
export DNS_PROFILE_MODE=clean

cat >"$test_tmp/bin/nmcli" <<'SH'
#!/bin/bash
printf 'nmcli %s\n' "$*" >>"$DNS_CALLS"

if [[ $* == "-t -f UUID,TYPE connection show" ]]; then
  printf 'wired:802-3-ethernet\nwifi:802-11-wireless\nvpn:vpn\n'
elif [[ $1 == "-g" && $3 == "connection" && $4 == "show" ]]; then
  if [[ $DNS_PROFILE_MODE == "legacy" && $5 == "wired" ]]; then
    printf 'yes\n1.1.1.1,1.0.0.1\nyes\n2606:4700:4700::1111\n'
  else
    printf 'no\n\nno\n\n'
  fi
elif [[ $* == "-t -f DEVICE,TYPE,STATE device status" ]]; then
  printf 'enp10s0:ethernet:connected\nlo:loopback:connected\n'
fi
SH
chmod +x "$test_tmp/bin/nmcli"

cat >"$test_tmp/bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$DNS_CALLS"
SH
chmod +x "$test_tmp/bin/systemctl"

export PATH="$test_tmp/bin:$PATH"
eval "$(sed -n '/^networkmanager_dns_connection()/,/^}/p' "$dns")"
eval "$(sed -n '/^connection_uses_dhcp_dns()/,/^}/p' "$dns")"
eval "$(sed -n '/^clear_connection_dns()/,/^}/p' "$dns")"
eval "$(sed -n '/^reapply_active_dns_connections()/,/^}/p' "$dns")"
eval "$(sed -n '/^reload_dns_stack()/,/^}/p' "$dns")"

: >"$DNS_CALLS"
dns_connections_changed=false
clear_connection_dns
[[ $dns_connections_changed == "false" ]] || fail "clean DHCP profiles were marked as changed"
if grep -F 'connection modify' "$DNS_CALLS" >/dev/null; then
  fail "clean DHCP profiles were rewritten"
fi

: >"$DNS_CALLS"
DNS_PROFILE_MODE=legacy
dns_connections_changed=false
clear_connection_dns
[[ $dns_connections_changed == "true" ]] || fail "legacy provider DNS was not marked for cleanup"
(( $(grep -Fc 'connection modify' "$DNS_CALLS") == 1 )) || fail "legacy DNS cleanup did not modify exactly one profile"
pass "DHCP only rewrites profiles that still carry DNS overrides"

: >"$DNS_CALLS"
dns_connections_changed=false
reload_dns_stack
grep -F 'nmcli general reload conf' "$DNS_CALLS" >/dev/null
grep -F 'nmcli general reload dns-full' "$DNS_CALLS" >/dev/null
if grep -F 'nmcli device reapply' "$DNS_CALLS" >/dev/null; then
  fail "provider changes reapplied the active connection"
fi

: >"$DNS_CALLS"
dns_connections_changed=true
reload_dns_stack
grep -F 'nmcli device reapply enp10s0' "$DNS_CALLS" >/dev/null || fail "legacy DHCP cleanup was not applied"
pass "DNS reload avoids DHCP churn except for legacy profile cleanup"

grep -F 'systemd-networkd.service' "$hardware_network" >/dev/null
grep -F 'systemd-networkd.socket' "$hardware_network" >/dev/null
grep -F '20-wlan.network' "$hardware_network" >/dev/null
grep -F 'omarchy-networkd-retired' "$hardware_network" >/dev/null
pass "hardware setup retires archinstall networkd state"

grep -F 'OMARCHY_UPGRADE_TO_QUATTRO_LIVE' "$migration" >/dev/null
grep -F 'systemctl disable --now "$unit"' "$migration" >/dev/null
grep -F 'systemctl stop systemd-networkd.service' "$migration" >/dev/null
grep -F 'NetworkManager.service' "$migration" >/dev/null
grep -F '20-wlan.network' "$migration" >/dev/null
pass "migration repairs upgraded systems with networkd still active"
