#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/install/helpers/managed-account.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

assert_normalized() {
  local input=$1 expected=$2 actual

  actual=$(managed_account_site_normalize "$input") || fail "website is accepted: $input"
  [[ $actual == "$expected" ]] || fail "website is normalized: $input" "expected=$expected actual=$actual"
}

assert_rejected() {
  local input=$1

  if managed_account_site_normalize "$input" >/dev/null; then
    fail "unsafe website is rejected: $input"
  fi
}

assert_normalized "https://School.Example/lessons/today" ".school.example"
assert_normalized "*.khanacademy.org" ".khanacademy.org"
assert_normalized ".sub.example.com:443" ".sub.example.com"
pass "URLs and wildcard hosts normalize to Squid domain ACLs"

for invalid in \
  "file://example.com/secret" \
  "https://user@example.com" \
  "https://example.com:8443" \
  "127.0.0.1" \
  "[::1]" \
  "localhost" \
  "printer.local" \
  "example..com" \
  "-bad.example" \
  "not a domain.example"; do
  assert_rejected "$invalid"
done
pass "local, numeric, credential-bearing, and malformed hosts are rejected"

for valid in kid kid-2 family_account; do
  managed_account_username_valid "$valid" || fail "managed username is accepted: $valid"
done
for invalid in root nobody "Kid" "kid.name" "../../kid" "this-username-is-more-than-thirty-two-characters"; do
  managed_account_username_valid "$invalid" && fail "managed username is rejected: $invalid"
done
pass "managed account names are safe for paths and systemd instances"

allowlist="$test_tmp/allowlist"
: >"$allowlist"
managed_account_allowlist_add "$allowlist" \
  "https://www.example.com/path" \
  "khanacademy.org" \
  "WWW.EXAMPLE.COM"
expected=$'.khanacademy.org\n.www.example.com'
actual=$(<"$allowlist")
[[ $actual == "$expected" ]] || fail "allowlist additions are normalized, sorted, and deduplicated" "expected=$expected actual=$actual"

managed_account_allowlist_remove "$allowlist" "https://www.example.com/anything"
[[ $(<"$allowlist") == ".khanacademy.org" ]] || fail "deny removes the normalized website host"
pass "allowlist updates are deterministic"

squid_config=$(managed_account_render_squid_config kid 42007 /etc/omarchy/managed-accounts/kid/allowlist)
grep -Fxq 'http_port 127.0.0.1:42007' <<<"$squid_config" || fail "Squid binds the account's loopback port"
grep -Fxq 'acl allowed_sites dstdomain "/etc/omarchy/managed-accounts/kid/allowlist"' <<<"$squid_config" ||
  fail "Squid reads the root-owned account allowlist"
grep -Fxq 'http_access allow local_client allowed_sites' <<<"$squid_config" || fail "Squid allows listed sites"
grep -Fxq 'http_access deny blocked_destinations' <<<"$squid_config" || fail "Squid blocks loopback, private, link-local, and multicast destinations"
grep -Fxq 'http_access deny all' <<<"$squid_config" || fail "Squid denies everything else"
! grep -q 'ssl_bump' <<<"$squid_config" || fail "managed browsing does not intercept TLS"
pass "Squid configuration is allowlist-only without TLS interception"

nft_config=$(printf '1001 42000\n1002 42001\n' | managed_account_render_nft_config)
grep -Fxq 'add rule inet omarchy_managed_accounts output meta skuid 1001 ip daddr 127.0.0.1 tcp dport 42000 accept' <<<"$nft_config" ||
  fail "the first managed UID can reach only its proxy"
grep -Fxq 'add rule inet omarchy_managed_accounts output meta skuid 1001 reject' <<<"$nft_config" ||
  fail "the first managed UID has all other egress rejected"
grep -Fxq 'add rule inet omarchy_managed_accounts output meta skuid 1002 ip daddr 127.0.0.1 tcp dport 42001 accept' <<<"$nft_config" ||
  fail "the second managed UID gets a distinct proxy"
grep -Fxq 'delete table inet omarchy_managed_accounts' <<<"$nft_config" || fail "firewall replacement removes the prior table atomically"
pass "nftables rules isolate multiple managed accounts by UID"

grep -Fq '99-omarchy-managed-no-autologin.conf' "$ROOT/bin/omarchy-managed" ||
  fail "adding a managed account overrides alternate SDDM autologin drop-ins"
grep -A4 -F "<<'CONF'" "$ROOT/bin/omarchy-managed" | grep -Fxq 'User=' ||
  fail "the SDDM override clears the autologin user"
grep -Fq 'cp -a "$omarchy_root/config/." "$home/.config/"' "$ROOT/bin/omarchy-managed" ||
  fail "new managed users get shipped Omarchy desktop defaults without administrator files"
grep -Fq '"$home/.local" "$home/.local/state" "$state_dir"' "$ROOT/bin/omarchy-managed" ||
  fail "new managed users own the intermediate directories for their Omarchy state"
grep -Fq '/dev/null "$done_dir/finalize-user"' "$ROOT/bin/omarchy-managed" &&
  grep -Fq '/dev/null "$done_dir/first-run-user"' "$ROOT/bin/omarchy-managed" ||
  fail "managed users skip the privileged and network-dependent first-run path"
grep -Fq 'install/user/default-keyring.sh' "$ROOT/bin/omarchy-managed" ||
  fail "new managed users initialize Omarchy's local keyring before Chromium starts"
grep -Fq 'Allowed websites (separate multiple with spaces)> ' "$ROOT/bin/omarchy-managed" ||
  fail "interactive setup explains how to enter multiple allowed websites"
grep -Fq 'Websites to allow (separate multiple with spaces)> ' "$ROOT/bin/omarchy-managed" &&
  grep -Fq 'username=$(choose_managed_account)' "$ROOT/bin/omarchy-managed" ||
  fail "interactive updates choose an account and explain how to enter multiple websites"
grep -Fq '"label":"Managed Accounts"' "$ROOT/default/omarchy/omarchy-menu.jsonc" &&
  grep -Fq '"label":"Allow Websites"' "$ROOT/default/omarchy/omarchy-menu.jsonc" &&
  grep -Fq '"label":"Remove Websites"' "$ROOT/default/omarchy/omarchy-menu.jsonc" &&
  grep -Fq '"label":"View Websites"' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "the Security menu exposes managed-account allowlist management"
grep -Fiq 'the Linux user and home directory were not deleted' "$ROOT/bin/omarchy-managed" ||
  fail "removing management preserves the user account"
pass "account lifecycle keeps the admin/managed login boundary safe"
