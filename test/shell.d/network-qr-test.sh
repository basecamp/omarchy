#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/nmcli" <<'EOF'
#!/bin/bash
if [[ $* == *"DEVICE,TYPE,STATE"* ]]; then
  printf 'eth0:ethernet:connected\nwlan0:wifi:connected\n'
elif [[ $* == *GENERAL.CON-UUID* ]]; then
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
  shift 3
  local output meta matrix payload arg with_meta=false
  local expected_matrix expected_security expected_ssid expected_iface="*"

  for arg in "$@"; do
    [[ $arg == "--meta" ]] && with_meta=true || expected_iface=$arg
  done

  export QR_NMCLI_FIELDS=$fields
  export QR_PAYLOAD_FILE="$tmp/payload"
  output=$(PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-qr" "$@")

  expected_matrix=$'100\n010\n001'
  if [[ $with_meta == "true" ]]; then
    meta=$(head -n1 <<<"$output")
    matrix=$(tail -n +2 <<<"$output")

    # The meta line leads with the shared interface, security, and SSID. With
    # no interface argument the helper detects one from the live host, so that
    # field is only pinned when the case pinned it.
    expected_security=${expected_payload#WIFI:T:}
    expected_security=${expected_security%%;*}
    expected_ssid=$(head -n1 <<<"$fields")
    [[ $meta == meta$'\t'$expected_iface$'\t'"$expected_security"$'\t'"$expected_ssid" ]] \
      || fail "$description leads with the interface, security, and SSID" "actual: $meta"
  else
    matrix=$output
  fi
  [[ $matrix == "$expected_matrix" ]] || fail "$description emits a compact module matrix" "expected: $expected_matrix\nactual: $matrix"

  payload=$(<"$QR_PAYLOAD_FILE")
  [[ $payload == "$expected_payload" ]] || fail "$description generates the Wi-Fi payload" "expected: $expected_payload\nactual: $payload"
  pass "$description"
}

run_success_case \
  "network QR helper escapes WPA credentials through stdin" \
  $'Cafe;Guest\\5G\nwpa-psk\np,a:ss;word\\42\nno\n' \
  'WIFI:T:WPA;S:Cafe\;Guest\\5G;P:p\,a\:ss\;word\\42;;' \
  --meta wlan0

# Without --meta the output stays a bare matrix, which pre-plugin clones of
# the network widget still parse.
run_success_case \
  "network QR helper keeps the bare matrix without --meta" \
  $'Cafe;Guest\\5G\nwpa-psk\np,a:ss;word\\42\nno\n' \
  'WIFI:T:WPA;S:Cafe\;Guest\\5G;P:p\,a\:ss\;word\\42;;' \
  wlan0

# With no interface argument the helper finds the connected Wi-Fi device.
run_success_case \
  "network QR helper detects the Wi-Fi interface" \
  $'Cafe Detected\nwpa-psk\nsecret\nno\n' \
  'WIFI:T:WPA;S:Cafe Detected;P:secret;;' \
  --meta

run_success_case \
  "network QR helper supports open networks" \
  $'Cafe Open\nnone\n\nno\n' \
  'WIFI:T:nopass;S:Cafe Open;P:;;' \
  --meta wlan0

run_success_case \
  "network QR helper marks hidden networks" \
  $'Hidden Network\nwpa-psk\nsecret\nyes\n' \
  'WIFI:T:WPA;S:Hidden Network;P:secret;H:true;;' \
  --meta wlan0

# NetworkManager models WEP as key-mgmt "none" plus a wep-key, which must not
# be mistaken for an open network.
run_success_case \
  "network QR helper encodes WEP networks" \
  $'Old Router\nnone\n\nno\nwep-secret\n' \
  'WIFI:T:WEP;S:Old Router;P:wep-secret;;' \
  --meta wlan0

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
