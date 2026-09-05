#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/sys/wlan0/wireless" "$tmp/sys/eth0"

call_log="$tmp/calls"

cat >"$tmp/bin/ip" <<'SH'
#!/bin/bash
printf 'ip\n' >>"$NS_CALL_LOG"
printf '1.1.1.1 via 192.168.1.1 dev %s src 192.168.1.50\n' "$NS_DEVICE"
SH

cat >"$tmp/bin/nmcli" <<'SH'
#!/bin/bash
if [[ $* == *GENERAL.STATE* ]]; then
  printf 'nmcli-show\n' >>"$NS_CALL_LOG"
  printf 'GENERAL.STATE:%s\nGENERAL.CONNECTION:%s\n' "$NS_NM_STATE" "$NS_SSID"
else
  printf 'nmcli-wifi-list\n' >>"$NS_CALL_LOG"
  printf '*:72\n'
fi
SH

cat >"$tmp/bin/iw" <<'SH'
#!/bin/bash
printf 'iw\n' >>"$NS_CALL_LOG"
printf '\tfreq: 5220\n'
SH

chmod +x "$tmp/bin/ip" "$tmp/bin/nmcli" "$tmp/bin/iw"

export PATH="$tmp/bin:$ROOT/bin:$PATH"
export NS_CALL_LOG="$call_log"
export NS_NM_STATE="100 (connected)"
export NS_SSID="Example"

# The command reads /sys/class/net directly, so the wireless branch can only be
# exercised with a wireless interface this machine actually has. Find one rather
# than assume a name, and skip the branch on a machine with no wifi.
wireless_device=""
for candidate in /sys/class/net/*/wireless; do
  [[ -d $candidate ]] || continue
  candidate=${candidate%/wireless}
  wireless_device=${candidate##*/}
  break
done

run_case() {
  export NS_DEVICE="$1"
  : >"$call_log"
}

if [[ -n $wireless_device ]]; then
  run_case "$wireless_device"
  output=$(omarchy-network-status)
  [[ $output == wifi$'\t'* ]] || fail "the full line still starts with the connection type"
  pass "the full line still starts with the connection type"

  run_case "$wireless_device"
  output=$(omarchy-network-status --type)
  [[ $output == "wifi" ]] || fail "--type answers with the type alone, got: $output"
  pass "--type answers with the connection type alone"

  run_case "$wireless_device"
  omarchy-network-status >/dev/null
  full_calls=$(wc -l <"$call_log")

  run_case "$wireless_device"
  omarchy-network-status --type >/dev/null
  type_calls=$(wc -l <"$call_log")

  (( type_calls < full_calls )) || fail "--type runs fewer commands than the full line ($type_calls vs $full_calls)"
  pass "--type runs fewer commands than the full line"

  run_case "$wireless_device"
  omarchy-network-status --type >/dev/null
  grep -q 'nmcli-wifi-list' "$call_log" && fail "--type must not scan the wifi list for a signal it does not print"
  grep -q '^iw$' "$call_log" && fail "--type must not ask iw for a frequency it does not print"
  pass "--type skips the signal and frequency lookups"

  run_case "$wireless_device"
  omarchy-network-status --type >/dev/null
  grep -q 'nmcli-show' "$call_log" || fail "--type still asks whether the device is connected"
  pass "--type still distinguishes connected from disconnected"

  NS_NM_STATE="30 (disconnected)"
  run_case "$wireless_device"
  output=$(omarchy-network-status --type)
  [[ $output == "disconnected" ]] || fail "--type reports a disconnected wireless device as disconnected, got: $output"
  pass "--type reports a disconnected wireless device the same way the full line does"
  NS_NM_STATE="100 (connected)"
fi

output=$(omarchy-network-status --nonsense 2>&1 || true)
[[ $output == *"--verbose|--type"* ]] || fail "usage names both modes"
pass "usage names both modes"
