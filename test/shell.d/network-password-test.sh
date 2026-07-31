#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/nmcli" <<'EOF'
#!/bin/bash
if [[ $* == *GENERAL.CON-UUID* ]]; then
  echo test-uuid
else
  printf '%s' "$PW_NMCLI_FIELDS"
fi
EOF
chmod +x "$tmp/bin/nmcli"

run_failure_case() {
  local description=$1 fields=$2 expected_error=$3
  local error

  export PW_NMCLI_FIELDS=$fields
  if PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-password" wlan0 >"$tmp/output" 2>"$tmp/error"; then
    fail "$description" "helper unexpectedly succeeded"
  fi
  error=$(<"$tmp/error")
  [[ $error == "$expected_error" ]] || fail "$description" "expected: $expected_error\nactual: $error"
  pass "$description"
}

# The password comes back raw -- no QR escaping -- because it is shown to a
# human, not embedded in a WIFI: payload.
export PW_NMCLI_FIELDS=$'wpa-psk\np,a:ss;word\\42\n'
output=$(PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-password" wlan0)
[[ $output == 'p,a:ss;word\42' ]] || fail "network password helper prints the raw password" "expected: p,a:ss;word\\42\nactual: $output"
pass "network password helper prints the raw password"

run_failure_case \
  "network password helper refuses open networks" \
  $'none\n\n' \
  "This network has no password"

# WEP looks like an open network (key-mgmt "none") but carries a wep-key.
export PW_NMCLI_FIELDS=$'none\n\nwep-secret\n'
output=$(PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-password" wlan0)
[[ $output == "wep-secret" ]] || fail "network password helper prints WEP keys" "expected: wep-secret\nactual: $output"
pass "network password helper prints WEP keys"

run_failure_case \
  "network password helper refuses enterprise networks" \
  $'wpa-eap\nsecret\n' \
  "Enterprise Wi-Fi has no shareable password"
