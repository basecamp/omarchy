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
  printf '%s' "$QR_NMCLI_FIELDS"
fi
EOF

cat >"$tmp/bin/qrencode" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  [[ $arg != WIFI:* ]] || exit 97
done
payload=$(</dev/stdin)
printf '%s' "$payload" >"$QR_PAYLOAD_FILE"
printf '##    \n  ##  \n    ##\n'
EOF
chmod +x "$tmp/bin/nmcli" "$tmp/bin/qrencode"

run_success_case() {
  local description=$1 fields=$2 expected_payload=$3
  local expected output payload

  export QR_NMCLI_FIELDS=$fields
  export QR_PAYLOAD_FILE="$tmp/payload"
  output=$(PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-qr" wlan0)
  expected=$'100\n010\n001'
  [[ $output == "$expected" ]] || fail "$description emits a compact module matrix" "expected: $expected\nactual: $output"

  payload=$(<"$QR_PAYLOAD_FILE")
  [[ $payload == "$expected_payload" ]] || fail "$description generates the Wi-Fi payload" "expected: $expected_payload\nactual: $payload"
  pass "$description"
}

run_success_case \
  "network QR helper escapes WPA credentials through stdin" \
  $'Cafe;Guest\\5G\nwpa-psk\np,a:ss;word\\42\nno\n' \
  'WIFI:T:WPA;S:Cafe\;Guest\\5G;P:p\,a\:ss\;word\\42;;'

run_success_case \
  "network QR helper supports open networks" \
  $'Cafe Open\nnone\n\nno\n' \
  'WIFI:T:nopass;S:Cafe Open;P:;;'

run_success_case \
  "network QR helper marks hidden networks" \
  $'Hidden Network\nwpa-psk\nsecret\nyes\n' \
  'WIFI:T:WPA;S:Hidden Network;P:secret;H:true;;'

# NetworkManager models WEP as key-mgmt "none" plus a wep-key, which must not
# be mistaken for an open network.
run_success_case \
  "network QR helper encodes WEP networks" \
  $'Old Router\nnone\n\nno\nwep-secret\n' \
  'WIFI:T:WEP;S:Old Router;P:wep-secret;;'

export QR_NMCLI_FIELDS=$'Enterprise\nwpa-eap\nsecret\nno\n'
export QR_PAYLOAD_FILE="$tmp/enterprise-payload"
if PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-qr" wlan0 >"$tmp/enterprise-output" 2>"$tmp/enterprise-error"; then
  fail "network QR helper rejects enterprise networks" "helper unexpectedly succeeded"
fi
enterprise_error=$(<"$tmp/enterprise-error")
expected_error="Enterprise Wi-Fi cannot be shared with a password QR code"
[[ $enterprise_error == "$expected_error" ]] || fail "network QR helper rejects enterprise networks" "expected: $expected_error\nactual: $enterprise_error"
[[ ! -e $QR_PAYLOAD_FILE ]] || fail "network QR helper rejects enterprise networks" "qrencode unexpectedly ran"
pass "network QR helper rejects enterprise networks"
