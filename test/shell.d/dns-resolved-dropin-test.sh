#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

dns="$ROOT/bin/omarchy-dns"

# The whole point: /etc/systemd/resolved.conf is an administrator's file, and a
# provider change must not carry off the DNSSEC=, Domains= or LLMNR settings
# that happen to share it.
if grep -nE '(tee|>)[[:space:]]*/etc/systemd/resolved\.conf([[:space:]]|$)' "$dns"; then
  fail "omarchy-dns never writes /etc/systemd/resolved.conf"
fi
grep -Fx 'RESOLVED_DNS_CONF=/etc/systemd/resolved.conf.d/20-omarchy-dns.conf' "$dns" >/dev/null ||
  fail "omarchy-dns owns a resolved drop-in beside its NetworkManager one"
pass "omarchy-dns writes a drop-in instead of replacing resolved.conf"

# resolved collects DNS= and FallbackDNS= across the main file and its drop-ins
# rather than letting the last one win, so a drop-in that only assigns would add
# its servers to whatever an older Omarchy left behind.
incomplete=$(awk '
  /write_resolved_dns <</ { block++; in_block = 1; has_dns = 0; has_fallback = 0; next }
  in_block && /^EOF$/ {
    if (!has_dns || !has_fallback) print "drop-in " block
    in_block = 0
    next
  }
  in_block && /^DNS=$/ { has_dns = 1 }
  in_block && /^FallbackDNS=$/ { has_fallback = 1 }
  END { if (block != 4) print "expected four drop-ins, found " block }
' "$dns")
[[ -z $incomplete ]] ||
  fail "every resolved drop-in clears both server lists before assigning" "$incomplete"
pass "resolved drop-ins clear both server lists before assigning"

# DNSOverTLS decides how the servers selected here are reached, so every mode
# names it rather than inheriting whatever the main file happens to say. A
# custom resolver that does not speak DoT would otherwise stop answering the
# moment an administrator had set DNSOverTLS=yes.
modes=$(awk '
  /write_resolved_dns <</ { in_block = 1; mode = "DHCP"; tls = "(unset)"; next }
  in_block && /^EOF$/ { print mode "=" tls; in_block = 0; next }
  in_block {
    if ($0 ~ /cloudflare-dns\.com/) mode = "Cloudflare"
    else if ($0 ~ /dns\.google/) mode = "Google"
    else if ($0 ~ /dns_servers/) mode = "Custom"
    if ($0 ~ /^DNSOverTLS=/) { tls = $0; sub(/^DNSOverTLS=/, "", tls) }
  }
' "$dns")

expected=$'Cloudflare=opportunistic\nGoogle=opportunistic\nDHCP=no\nCustom=no'
[[ $modes == "$expected" ]] ||
  fail "every mode pins the transport its own servers are reached over" "got:$(printf '\n%s' "$modes")"
pass "every mode pins the transport its own servers are reached over"

# Reporting has to follow the settings to the drop-in, or a machine that still
# carries an older Omarchy's servers in the main file answers with them.
if (( EUID == 0 )) || unshare --user --map-root-user true 2>/dev/null; then
  probe() {
    local main=$1 dropin=$2 fixture
    fixture=$(mktemp -d)
    mkdir -p "$fixture/systemd/resolved.conf.d" "$fixture/nm"
    printf '%s' "$main" >"$fixture/systemd/resolved.conf"
    if [[ -n $dropin ]]; then
      printf '%s' "$dropin" >"$fixture/systemd/resolved.conf.d/20-omarchy-dns.conf"
    fi

    unshare --user --map-root-user --mount bash -c '
      mount --bind "$1/systemd" /etc/systemd
      mount --bind "$1/nm" /etc/NetworkManager
      bash "$2"
    ' _ "$fixture" "$dns" 2>/dev/null
    rm -rf "$fixture"
  }

  stale_main=$'[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com\nDNSSEC=yes\n'

  [[ $(probe "$stale_main" $'[Resolve]\nDNS=\nFallbackDNS=\nDNSOverTLS=no\n') == "DHCP" ]] ||
    fail "selecting DHCP reports DHCP even where an older Omarchy wrote servers into resolved.conf"
  pass "selecting DHCP reports DHCP over servers left in the main file"

  [[ $(probe "$stale_main" $'[Resolve]\nDNS=\nDNS=8.8.8.8#dns.google\nFallbackDNS=\n') == "Google" ]] ||
    fail "a drop-in provider outranks servers left in the main file"
  pass "a drop-in provider outranks servers left in the main file"

  [[ $(probe $'[Resolve]\nDNS=8.8.8.8#dns.google\n' "") == "Google" ]] ||
    fail "a machine with no drop-in yet still reports from resolved.conf"
  pass "a machine with no drop-in yet still reports from resolved.conf"

  [[ $(probe "$stale_main" $'[Resolve]\nDNS=\nDNS=192.168.1.1\nFallbackDNS=\n') == "Custom" ]] ||
    fail "a drop-in naming servers Omarchy does not ship reports Custom"
  pass "a drop-in naming servers Omarchy does not ship reports Custom"
else
  pass "no unprivileged user namespace; skipping the reporting probes"
fi
