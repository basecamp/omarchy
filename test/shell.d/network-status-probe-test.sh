#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

STATUS="$ROOT/bin/omarchy-network-status"

# Load the address classifier and probe selection on their own, so the
# reachability rules can be checked without any real network.
eval "$(sed -n '/^is_public_ipv4()/,/^}$/p' "$STATUS")"
eval "$(sed -n '/^configured_dns_servers()/,/^}$/p' "$STATUS")"
eval "$(sed -n '/^internet_probes()/,/^}$/p' "$STATUS")"

fallback_probes=(1.1.1.1 8.8.8.8 9.9.9.9)
max_probes=3

for ip in 8.8.8.8 1.0.0.1 208.67.222.222 172.15.0.1 172.32.0.1 192.169.0.1 100.63.0.1; do
  is_public_ipv4 "$ip" || fail "public address is usable as a probe: $ip"
done
pass "public addresses are usable as probes"

# A resolver on the LAN, on loopback, or outside unicast IPv4 proves nothing
# about internet reachability.
for ip in 127.0.0.53 192.168.1.4 10.0.0.1 172.16.5.5 172.31.255.1 169.254.1.1 \
  100.64.0.1 0.0.0.0 224.0.0.1 2001:4860:4860::8888 999.1.1.1 8.8.8 abc ""; do
  ! is_public_ipv4 "$ip" || fail "address is rejected as a probe: ${ip:-<empty>}"
done
pass "non-public and malformed addresses are rejected as probes"

probes_for() {
  local dns_output=$1 stub probes

  stub=$(mktemp -d)
  cat >"$stub/resolvectl" <<EOF
#!/bin/bash
[[ \$1 == "dns" ]] && cat <<'DNS'
$dns_output
DNS
EOF
  chmod +x "$stub/resolvectl"
  probes=$(PATH="$stub:$PATH" bash -c "$(declare -f is_public_ipv4 configured_dns_servers internet_probes)
    fallback_probes=(1.1.1.1 8.8.8.8 9.9.9.9)
    max_probes=3
    internet_probes" | tr '\n' ' ')
  rm -rf "$stub"
  printf '%s' "${probes% }"
}

[[ $(probes_for 'Global: 8.8.8.8 8.8.4.4 9.9.9.9') == "8.8.8.8 8.8.4.4 9.9.9.9" ]] ||
  fail "configured public resolvers are probed" "got: $(probes_for 'Global: 8.8.8.8 8.8.4.4 9.9.9.9')"
pass "configured public resolvers are probed"

# `omarchy dns DHCP` typically yields a resolver inside the LAN. Probing it
# would report the internet as reachable whenever the router is up.
[[ $(probes_for 'Link 2 (wlp3s0): 192.168.1.4') == "1.1.1.1 8.8.8.8 9.9.9.9" ]] ||
  fail "a LAN-only resolver falls back to public probes" "got: $(probes_for 'Link 2 (wlp3s0): 192.168.1.4')"
pass "a LAN-only resolver falls back to public probes"

[[ $(probes_for 'Global: 2001:4860:4860::8888') == "1.1.1.1 8.8.8.8 9.9.9.9" ]] ||
  fail "IPv6-only resolvers fall back to public probes"
pass "IPv6-only resolvers fall back to public probes"

# The whole point: more than one address, so a network that blocks a single
# well-known resolver does not read as an outage.
probes=$(probes_for 'Global: 1.1.1.1 1.0.0.1')
(( $(wc -w <<<"$probes") > 1 )) || fail "more than one address is probed" "got: $probes"
pass "more than one address is probed"

# The router lookup must stay on a fixed public address: pointing it at a
# configured resolver would resolve an on-link route instead of the default one.
grep -q '^route_probe=' "$STATUS" || fail "route lookup uses a dedicated probe address"
grep -q 'ip route get "$route_probe"' "$STATUS" || fail "route lookup uses the dedicated probe address"
grep -q 'ip -j route get "$route_probe"' "$STATUS" || fail "verbose route lookup uses the dedicated probe address"
pass "route lookup uses a dedicated public address"

# An unreachable internet must still report as unreachable.
stub=$(mktemp -d)
cat >"$stub/ping" <<'PING'
#!/bin/bash
host=${!#}
if [[ $host == 192.168.1.1 ]]; then
  echo "64 bytes from $host: icmp_seq=1 ttl=64 time=1.23 ms"
  exit 0
fi
exit 1
PING
chmod +x "$stub/ping"
eval "$(sed -n '/^ping_latency_ms()/,/^}$/p' "$STATUS")"
eval "$(sed -n '/^ping_internet_ms()/,/^}$/p' "$STATUS")"
workdir=$(mktemp -d)
result=$(PATH="$stub:$PATH" ping_internet_ms "$workdir")
rm -rf "$stub" "$workdir"
[[ -z $result ]] || fail "an unreachable internet reports no latency" "got: $result"
pass "an unreachable internet reports no latency"
