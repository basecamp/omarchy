#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/nmcli" <<'EOF'
#!/bin/bash
args=("$@")
log="$NM_LOG"
joined="${args[*]}"

if [[ $joined == *"connection modify"* || $joined == *"connection add"* ]]; then
  printf '%s\n' "${args[@]}" >>"$log"
  printf -- '---\n' >>"$log"
  exit 0
fi

if [[ $joined == *"device reapply"* || $joined == *"device connect"* || $joined == *"connection up"* ]]; then
  printf '%s\n' "${args[@]}" >>"$log"
  printf -- '---\n' >>"$log"
  exit 0
fi

if [[ $joined == *"DEVICE,TYPE,STATE"* && $joined == *"device status"* ]]; then
  printf 'eth0:ethernet:connected\nwlan0:wifi:connected\nunm0:ethernet:unmanaged\n'
  exit 0
fi

if [[ $joined == *"UUID,TYPE"* && $joined == *"connection show"* ]]; then
  printf '11111111-1111-1111-1111-111111111111:802-3-ethernet\n'
  exit 0
fi

if [[ $joined == *"GENERAL.CONNECTION"* ]]; then
  printf '%s\n' "${NM_ACTIVE_CONNECTION:-Wired eth0}"
  exit 0
fi

if [[ $joined == *"connection.interface-name"* ]]; then
  echo eth0
  exit 0
fi

if [[ $joined == *"connection.autoconnect"* ]]; then
  echo yes
  exit 0
fi

if [[ $joined == *"connection.id"* ]]; then
  echo "Wired eth0"
  exit 0
fi

if [[ $joined == *"802-3-ethernet.mac-address"* ]]; then
  exit 0
fi

if [[ $joined == *"ipv4.method"* ]]; then
  printf '%s\n' "${NM_METHOD:-auto}"
  exit 0
fi

if [[ $joined == *"ipv4.addresses"* ]]; then
  [[ ${NM_METHOD:-auto} == manual ]] && echo '192.168.1.10/24'
  exit 0
fi

if [[ $joined == *"ipv4.gateway"* ]]; then
  [[ ${NM_METHOD:-auto} == manual ]] && echo '192.168.1.1'
  exit 0
fi

if [[ $joined == *"ipv4.dns"* ]]; then
  [[ ${NM_METHOD:-auto} == manual ]] && echo '1.1.1.1'
  exit 0
fi

if [[ $joined == *"IP4.ADDRESS"* ]]; then
  [[ ${NM_STATE:-connected} == connected ]] && echo '192.168.1.10/24'
  exit 0
fi

if [[ $joined == *"IP4.GATEWAY"* ]]; then
  [[ ${NM_STATE:-connected} == connected ]] && echo '192.168.1.1'
  exit 0
fi

exit 0
EOF
chmod +x "$tmp/bin/nmcli"

export NM_LOG="$tmp/nmcli.log"
export NM_STATE=connected
export NM_METHOD=manual
export NM_ACTIVE_CONNECTION="Wired eth0"

output=$(PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-eth-config" list)
[[ $output == *$'eth0\t'* ]] || fail "network eth-config lists managed ethernet devices" "missing eth0: $output"
[[ $output != *wlan0* ]] || fail "network eth-config skips Wi-Fi devices" "wlan0 leaked: $output"
[[ $output != *unm0* ]] || fail "network eth-config skips unmanaged ethernet devices" "unm0 leaked: $output"
[[ $output == *$'manual\t192.168.1.10\t24\t192.168.1.1\t1.1.1.1'* ]] || fail "network eth-config reports manual IPv4 profile" "missing manual fields: $output"
pass "network eth-config lists managed wired NICs and their IPv4 mode"

: >"$NM_LOG"
PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-eth-config" set eth0 dhcp >/dev/null
modify=$(<"$NM_LOG")
method=$(awk '/^ipv4.method$/ { getline; print; exit }' <<<"$modify")
addresses=$(awk '/^ipv4.addresses$/ { getline; print; exit }' <<<"$modify")
[[ $method == auto ]] || fail "network eth-config switches a NIC to DHCP" "method: $method"
[[ -z $addresses ]] || fail "network eth-config clears manual addresses on DHCP" "addresses: $addresses"
pass "network eth-config set dhcp switches a NIC to automatic DHCP"

: >"$NM_LOG"
PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-eth-config" set eth0 manual 10.0.0.5 24 10.0.0.1 >/dev/null
modify=$(<"$NM_LOG")
method=$(awk '/^ipv4.method$/ { getline; print; exit }' <<<"$modify")
addresses=$(awk '/^ipv4.addresses$/ { getline; print; exit }' <<<"$modify")
gateway=$(awk '/^ipv4.gateway$/ { getline; print; exit }' <<<"$modify")
[[ $method == manual ]] || fail "network eth-config switches a NIC to manual" "method: $method"
[[ $addresses == 10.0.0.5/24 ]] || fail "network eth-config writes the static address" "addresses: $addresses"
[[ $gateway == 10.0.0.1 ]] || fail "network eth-config writes the gateway" "gateway: $gateway"
pass "network eth-config set manual writes static IPv4 settings"
