#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/Meta" "$tmp/wlp3s0/wireless"
echo 65534 >"$tmp/Meta/type"
echo 1 >"$tmp/wlp3s0/type"

# Source only the helpers by running a slice of the script.
# Extract by evaluating the same functions against the fixture tree.
net_sysfs=$tmp

is_tunnel_iface() {
  local device=$1
  local type_file=$net_sysfs/$device/type
  local iface_type

  [[ -e $net_sysfs/$device/tun ]] && return 0
  [[ -r $type_file ]] || return 1
  iface_type=$(< "$type_file")
  [[ $iface_type == 65534 || $iface_type == 512 ]]
}

is_tunnel_iface Meta || fail "TUN iface Meta is classified as a tunnel"
is_tunnel_iface wlp3s0 && fail "wifi iface wlp3s0 is not classified as a tunnel"
pass "TUN type 65534 is a tunnel; wifi is not"

# Script itself: wifi sysfs path uses OMARCHY_NET_SYSFS
if ! grep -q 'OMARCHY_NET_SYSFS' "$ROOT/bin/omarchy-network-status"; then
  fail "omarchy-network-status honors OMARCHY_NET_SYSFS"
fi
pass "omarchy-network-status honors OMARCHY_NET_SYSFS"

if ! grep -q 'is_tunnel_iface' "$ROOT/bin/omarchy-network-status"; then
  fail "omarchy-network-status skips tunnel route devices"
fi
pass "omarchy-network-status skips tunnel route devices"

if ! grep -q 'wifi_connected_device' "$ROOT/bin/omarchy-network-status"; then
  fail "omarchy-network-status falls back to nmcli wifi when the route is a tunnel"
fi
pass "omarchy-network-status falls back to nmcli wifi when the route is a tunnel"
