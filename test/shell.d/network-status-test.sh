#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$stub_bin"

cat >"$stub_bin/ip" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$IP_CALLS"

case "$*" in
  "-j route show table main default")
    printf '%s\n' '[{"dst":"default","gateway":"192.0.2.1","dev":"wlp4s0","prefsrc":"192.0.2.15","metric":600}]'
    ;;
  "-j addr show wlp4s0")
    printf '%s\n' '[{"addr_info":[{"family":"inet","local":"192.0.2.15","prefixlen":24}]}]'
    ;;
  *)
    exit 1
    ;;
esac
SH

cat >"$stub_bin/ping" <<'SH'
#!/bin/bash
printf '%s\n' '64 bytes from target: icmp_seq=1 ttl=64 time=1.0 ms'
SH

chmod +x "$stub_bin/ip" "$stub_bin/ping"

IP_CALLS="$test_tmp/ip-calls" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-network-status" --verbose >"$test_tmp/status"

grep -qx $'iface\twlp4s0' "$test_tmp/status" || fail "network status selects the physical default route"
grep -qx $'ip\t192.0.2.15' "$test_tmp/status" || fail "network status reports the physical interface address"
grep -qx $'gateway\t192.0.2.1' "$test_tmp/status" || fail "network status reports the physical gateway"
if grep -q 'route get' "$test_tmp/ip-calls"; then
  fail "network status bypasses policy routing installed by VPNs"
fi

pass "network status ignores VPN policy routes"
