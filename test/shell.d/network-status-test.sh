#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

status_script="$ROOT/bin/omarchy-network-status"
stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

# Make the selected interface look like a real connected secondary adapter.
cat >"$stub_dir/ip" <<'STUB'
#!/bin/bash
case "$*" in
  "route get 1.1.1.1")
    printf '1.1.1.1 via 192.168.68.1 dev wlp0s20u1 src 192.168.68.51\n'
    ;;
  "-j addr show wlp3s0")
    printf '[{"addr_info":[{"family":"inet","local":"10.0.0.2","prefixlen":24}]}]\n'
    ;;
  "-j route show default dev wlp3s0")
    printf '[{"gateway":"10.0.0.1"}]\n'
    ;;
  *)
    :
    ;;
esac
STUB

cat >"$stub_dir/nmcli" <<'STUB'
#!/bin/bash
case "$*" in
  *'GENERAL.STATE,GENERAL.CONNECTION dev show wlp3s0'*)
    printf '100:TestNet\n'
    ;;
  *'IN-USE,SIGNAL dev wifi list ifname wlp3s0'*)
    printf '*:90\n'
    ;;
  *)
    :
    ;;
esac
STUB

cat >"$stub_dir/iw" <<'STUB'
#!/bin/bash
cat <<'OUT'
Connected to 00:11:22:33:44:55 (on wlp3s0)
	SSID: TestNet
	freq: 5180.0
	signal: -50 dBm
	tx bitrate: 433.3 MBit/s
OUT
STUB

cat >"$stub_dir/omarchy-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

cat >"$stub_dir/ping" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${PING_LOG:?}"
printf '64 bytes from test: time=12.34 ms\n'
STUB

chmod +x "$stub_dir"/*
PING_LOG="$stub_dir/ping.log" \
  PATH="$stub_dir:$PATH" \
  bash "$status_script" --verbose --iface wlp3s0 >"$stub_dir/output"

output=$(<"$stub_dir/output")
pings=$(<"$stub_dir/ping.log")

if [[ $output == *$'iface\twlp3s0'* ]]; then
  pass "status reports the selected interface"
else
  fail "status reports the selected interface" "output was: $output"
fi

if [[ $output == *$'ip\t10.0.0.2'* && $output == *$'gateway\t10.0.0.1'* ]]; then
  pass "status reports the selected interface's address and gateway"
else
  fail "status reports the selected interface's address and gateway" "output was: $output"
fi

if [[ $(grep -c -- '-I wlp3s0' "$stub_dir/ping.log") == 2 ]]; then
  pass "status binds both gateway and internet probes to the selected interface"
else
  fail "status binds both gateway and internet probes to the selected interface" \
    "ping invocations were: $pings"
fi

if grep -q -- '-I wlp3s0 10.0.0.1' "$stub_dir/ping.log"; then
  pass "status binds the gateway probe to the selected interface"
else
  fail "status binds the gateway probe to the selected interface" \
    "ping invocations were: $pings"
fi

if grep -q -- '-I wlp3s0 1.1.1.1' "$stub_dir/ping.log"; then
  pass "status binds the internet probe to the selected interface"
else
  fail "status binds the internet probe to the selected interface" \
    "ping invocations were: $pings"
fi
