#!/bin/bash

# Exercises classify_dns_servers / current_dns_provider without rewriting the
# host NetworkManager or resolved configuration. The classifier is extracted
# into a throwaway script so the production omarchy-dns binary is not sourced
# (it is a full command, not a library).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

dns_bin="$ROOT/bin/omarchy-dns"

# Pull the classifier body from the real command so the test tracks the
# production definition rather than a duplicated copy that can drift.
classifier_src=$(mktemp)
trap 'rm -f "$classifier_src"' EXIT

awk '
  /^classify_dns_servers\(\)/ { printing = 1 }
  printing { print }
  printing && /^}$/ { exit }
' "$dns_bin" >"$classifier_src"

grep -q 'classify_dns_servers()' "$classifier_src" ||
  fail "omarchy-dns defines classify_dns_servers for stock-provider matching"

# shellcheck disable=SC1090
source "$classifier_src"

expect_class() {
  local input="$1"
  local want="$2"
  local got

  got=$(classify_dns_servers "$input")
  [[ $got == "$want" ]] ||
    fail "classify_dns_servers reports $want for: $input" "got: $got"
}

# Empty / whitespace-only is DHCP (no global override).
expect_class "" "DHCP"
expect_class "   " "DHCP"
expect_class "," "DHCP"
pass "empty DNS list classifies as DHCP"

# Exact stock Cloudflare presets written by omarchy-dns Cloudflare.
expect_class "1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001" "Cloudflare"
expect_class "1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com" "Cloudflare"
expect_class "dns+tls://1.1.1.1#cloudflare-dns.com" "Cloudflare"
pass "stock Cloudflare server lists classify as Cloudflare"

# Exact stock Google presets.
expect_class "8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844" "Google"
expect_class "8.8.8.8#dns.google 8.8.4.4#dns.google" "Google"
pass "stock Google server lists classify as Google"

# Custom list that merely contains a public resolver as secondary (#10245).
expect_class "20.20.20.3 1.1.1.1" "Custom"
expect_class "20.20.20.3,1.1.1.1" "Custom"
expect_class "192.168.1.1,1.1.1.1" "Custom"
expect_class "10.0.0.1 8.8.8.8" "Custom"
expect_class "9.9.9.9,1.1.1.1,8.8.8.8" "Custom"
expect_class "1.1.1.1,8.8.8.8" "Custom"
pass "custom lists that include public resolvers classify as Custom"

# Pure custom without any stock addresses.
expect_class "192.168.1.1,10.0.0.1" "Custom"
expect_class "9.9.9.9#dns.quad9.net" "Custom"
pass "pure custom server lists classify as Custom"
