#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

dns="$ROOT/bin/omarchy-dns"
hardware_network="$ROOT/install/hardware/network.sh"
migration="$ROOT/migrations/1782002156.sh"

! grep -F 'systemd-networkd' "$dns" >/dev/null || fail "omarchy-dns no longer restarts systemd-networkd"
grep -F 'NetworkManager/conf.d/20-omarchy-dns.conf' "$dns" >/dev/null || fail "omarchy-dns writes the NetworkManager DNS drop-in"
grep -F '[global-dns-domain-*]' "$dns" >/dev/null || fail "omarchy-dns writes a global DNS domain section"
grep -F 'ipv4.ignore-auto-dns yes' "$dns" >/dev/null || fail "omarchy-dns can ignore DHCP DNS on a connection"
grep -F 'ipv4.ignore-auto-dns no' "$dns" >/dev/null || fail "omarchy-dns can restore DHCP DNS on a connection"
grep -F 'nmcli device reapply' "$dns" >/dev/null || fail "omarchy-dns reapplies the active device profile"
grep -F 'nmcli general reload conf' "$dns" >/dev/null || fail "omarchy-dns reloads NetworkManager configuration"
grep -F 'nmcli general reload dns-full' "$dns" >/dev/null || fail "omarchy-dns reloads NetworkManager DNS"
if grep -F 'nmcli general reload conf,dns-full' "$dns" >/dev/null; then
  fail "omarchy-dns must not push DNS before reapplying active profiles"
fi
pass "omarchy-dns configures DNS through NetworkManager"

grep -F 'systemd-networkd.service' "$hardware_network" >/dev/null || fail "hardware setup retires systemd-networkd.service"
grep -F 'systemd-networkd.socket' "$hardware_network" >/dev/null || fail "hardware setup retires the systemd-networkd socket"
grep -F '20-wlan.network' "$hardware_network" >/dev/null || fail "hardware setup clears the archinstall 20-wlan.network profile"
grep -F 'omarchy-networkd-retired' "$hardware_network" >/dev/null || fail "hardware setup marks networkd retired"
pass "hardware setup retires archinstall networkd state"

grep -F 'OMARCHY_UPGRADE_TO_QUATTRO_LIVE' "$migration" >/dev/null || fail "migration leaves the live upgrade environment alone"
grep -F 'systemctl disable --now "$unit"' "$migration" >/dev/null || fail "migration disables the networkd units it finds"
grep -F 'systemctl stop systemd-networkd.service' "$migration" >/dev/null || fail "migration stops systemd-networkd.service"
grep -F 'NetworkManager.service' "$migration" >/dev/null || fail "migration hands the network back to NetworkManager"
grep -F '20-wlan.network' "$migration" >/dev/null || fail "migration clears the archinstall 20-wlan.network profile"
pass "migration repairs upgraded systems with networkd still active"
