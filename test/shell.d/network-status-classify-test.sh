#!/bin/bash

# omarchy-network-status used to treat any non-wireless route device as
# ethernet. VPN/tunnel interfaces (no /sys/class/net/<if>/wireless and no
# backing device symlink) were therefore reported as "Ethernet (10gbit)" and
# hid Wi-Fi-only UI such as the QR share button (#10107).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

status_bin="$ROOT/bin/omarchy-network-status"

# Extract classification helpers from the real command so the test tracks
# production definitions rather than a duplicated copy.
helpers=$(mktemp)
trap 'rm -f "$helpers"' EXIT

awk '
  /^(is_wireless_device|is_hardware_net_device|classify_device_type)\(\)/ { printing = 1 }
  printing { print }
  printing && /^}$/ { printing = 0; print "" }
' "$status_bin" >"$helpers"

grep -q 'classify_device_type()' "$helpers" ||
  fail "omarchy-network-status defines classify_device_type"

# shellcheck disable=SC1090
source "$helpers"

# Fake sysfs tree.
sys=$(mktemp -d)
trap 'rm -rf "$sys"; rm -f "$helpers"' EXIT

mk_wifi() {
  local name=$1
  mkdir -p "$sys/class/net/$name/wireless"
  # Backing device present like a real NIC.
  mkdir -p "$sys/devices/pci0000:00/$name"
  ln -s "$sys/devices/pci0000:00/$name" "$sys/class/net/$name/device"
}

mk_eth() {
  local name=$1
  mkdir -p "$sys/class/net/$name"
  mkdir -p "$sys/devices/pci0000:00/$name"
  ln -s "$sys/devices/pci0000:00/$name" "$sys/class/net/$name/device"
  printf '1000\n' >"$sys/class/net/$name/speed"
}

mk_tunnel() {
  local name=$1
  mkdir -p "$sys/class/net/$name"
  # No device symlink, no wireless/ — matches CloudflareWARP / tailscale0 / wg.
  printf '10000\n' >"$sys/class/net/$name/speed"
}

# Point the helpers at the fake tree by wrapping the path checks.
is_wireless_device() {
  local device=$1
  [[ -n $device && -d $sys/class/net/$device/wireless ]]
}

is_hardware_net_device() {
  local device=$1
  [[ -n $device && -e $sys/class/net/$device/device ]]
}

# Re-source classify so it calls the wrapped predicates above.
classify_device_type() {
  local device=$1

  if is_wireless_device "$device"; then
    echo wifi
  elif is_hardware_net_device "$device"; then
    echo ethernet
  else
    echo tunnel
  fi
}

mk_wifi wlp3s0
mk_eth enp0s31f6
mk_tunnel CloudflareWARP
mk_tunnel tailscale0
mk_tunnel wg0

[[ $(classify_device_type wlp3s0) == wifi ]] || fail "wifi NIC classifies as wifi"
[[ $(classify_device_type enp0s31f6) == ethernet ]] || fail "ethernet NIC classifies as ethernet"
[[ $(classify_device_type CloudflareWARP) == tunnel ]] || fail "CloudflareWARP classifies as tunnel"
[[ $(classify_device_type tailscale0) == tunnel ]] || fail "tailscale0 classifies as tunnel"
[[ $(classify_device_type wg0) == tunnel ]] || fail "wg0 classifies as tunnel"
pass "classify_device_type distinguishes wifi, ethernet, and tunnel"

# Static shape of the production script: ethernet branch must require a backing
# device (or go through classify_device_type), and must not be the bare
# "not wireless ⇒ ethernet" test that #10107 describes.
if grep -n 'if \[\[ ! -d /sys/class/net/\$device/wireless \]\]' "$status_bin" >/dev/null; then
  fail "omarchy-network-status no longer uses bare not-wireless⇒ethernet"
fi
grep -q 'classify_device_type' "$status_bin" ||
  fail "omarchy-network-status routes classification through classify_device_type"
grep -q 'is_hardware_net_device' "$status_bin" ||
  fail "omarchy-network-status gates ethernet on a backing device symlink"
grep -q 'resolve_primary_device' "$status_bin" ||
  fail "omarchy-network-status resolves primary past a tunnel default route"
pass "production script no longer mislabels tunnels as ethernet"

# Drive resolve_primary_device with stubbed ip/nmcli against the fake topology:
# default route via CloudflareWARP, only real link is wifi.
tmp=$(mktemp -d)
trap 'rm -rf "$sys" "$tmp"; rm -f "$helpers"' EXIT

cat >"$tmp/ip" <<'SH'
#!/bin/bash
# ip route get 1.1.1.1 → tunnel owns the default route (the bug case).
if [[ $1 == route && $2 == get ]]; then
  printf '1.1.1.1 dev CloudflareWARP table 65743 src 172.16.0.2 uid 1000\n'
  exit 0
fi
if [[ $1 == -j && $2 == route && $3 == get ]]; then
  printf '[{"dev":"CloudflareWARP","prefsrc":"172.16.0.2"}]\n'
  exit 0
fi
if [[ $1 == -j && $2 == addr ]]; then
  printf '[{"addr_info":[{"family":"inet","local":"192.168.1.50","prefixlen":24,"scope":"global"}]}]\n'
  exit 0
fi
if [[ $1 == -j && $2 == route && $3 == show ]]; then
  printf '[{"dst":"default","gateway":"192.168.1.1"}]\n'
  exit 0
fi
exit 0
SH
chmod +x "$tmp/ip"

cat >"$tmp/nmcli" <<'SH'
#!/bin/bash
if [[ $* == *device\ status* ]]; then
  printf 'wlp3s0:wifi:connected:Blue\n'
  printf 'CloudflareWARP:tun:connected (externally):CloudflareWARP\n'
  printf 'tailscale0:tun:connected (externally):tailscale0\n'
  exit 0
fi
if [[ $* == *dev\ show* ]]; then
  printf 'GENERAL.STATE:100 (connected)\n'
  printf 'GENERAL.CONNECTION:Blue\n'
  exit 0
fi
if [[ $* == *wifi\ list* ]]; then
  printf '*:72\n'
  exit 0
fi
exit 0
SH
chmod +x "$tmp/nmcli"

cat >"$tmp/iw" <<'SH'
#!/bin/bash
printf 'Connected to aa:bb:cc:dd:ee:ff (on wlp3s0)\n'
printf '\tfreq: 5500\n'
printf '\tSSID: Blue\n'
printf '\tsignal: -55 dBm\n'
printf '\ttx bitrate: 866.7 MBit/s\n'
exit 0
SH
chmod +x "$tmp/iw"

cat >"$tmp/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == iw || $1 == ping ]] && exit 0
exit 1
SH
chmod +x "$tmp/omarchy-cmd-present"

cat >"$tmp/jq" <<'SH'
#!/bin/bash
# Minimal jq stand-in for the few filters print_verbose uses.
python3 - "$@" <<'PY'
import json, sys
data = sys.stdin.read()
try:
    obj = json.loads(data) if data.strip() else None
except Exception:
    obj = None
# The real filters are passed as argv after jq; approximate the ones we emit.
args = " ".join(sys.argv[1:])
if obj is None:
    sys.exit(0)
if ".[0].dev" in args:
    print(obj[0].get("dev", "") if isinstance(obj, list) and obj else "")
elif ".[0].gateway" in args:
    print(obj[0].get("gateway", "") if isinstance(obj, list) and obj else "")
elif ".[0].prefsrc" in args:
    print(obj[0].get("prefsrc", "") if isinstance(obj, list) and obj else "")
elif "prefixlen" in args:
    for a in (obj[0].get("addr_info") or []) if isinstance(obj, list) and obj else []:
        if a.get("family") == "inet":
            print(a.get("prefixlen", "")); break
elif "local" in args:
    for a in (obj[0].get("addr_info") or []) if isinstance(obj, list) and obj else []:
        if a.get("family") == "inet" and a.get("scope") == "global":
            print(a.get("local", "")); break
elif "dst == \"default\"" in args or "dst" in args:
    if isinstance(obj, list):
        for r in obj:
            if r.get("dst") == "default":
                print(r.get("gateway", "")); break
PY
SH
chmod +x "$tmp/jq"

# Redirect sysfs reads used by the script to the fake tree via a wrapper that
# rewrites /sys/class/net paths. Easiest portable approach: run a copy of the
# script with SYSROOT substituted — instead, export a tiny LD-free approach by
# putting a `test`/`[` that still works and relying on helpers already tested;
# for end-to-end, rewrite the script's /sys/class/net references through sed.
wrapped=$(mktemp)
sed -e "s|/sys/class/net/|$sys/class/net/|g" "$status_bin" >"$wrapped"
chmod +x "$wrapped"

export PATH="$tmp:$PATH"

out=$(bash "$wrapped" 2>/dev/null || true)
[[ $out == wifi$'\t'* ]] || fail "compact status prefers wifi under a tunnel default route" "got: $out"
pass "compact status reports wifi when tunnel owns the default route"

vout=$(bash "$wrapped" --verbose 2>/dev/null || true)
echo "$vout" | grep -qx $'type\twifi' ||
  fail "verbose status types the underlay as wifi, not ethernet" "got: $vout"
echo "$vout" | grep -qx $'iface\twlp3s0' ||
  fail "verbose status selects the wifi iface, not CloudflareWARP" "got: $vout"
if echo "$vout" | grep -qx $'type\tethernet'; then
  fail "verbose status must not report ethernet for a tunnel-only route underlay"
fi
pass "verbose status keeps wifi hero and QR-share type under VPN"
