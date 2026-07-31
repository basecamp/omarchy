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
  printf 'Cafe;Guest\\5G\nwpa-psk\np,a:ss;word\\42\nno\n'
fi
EOF

cat >"$tmp/bin/qrencode" <<'EOF'
#!/bin/bash
printf '%s' "${@: -1}" >"$QR_PAYLOAD_FILE"
printf '##    \n  ##  \n    ##\n'
EOF
chmod +x "$tmp/bin/nmcli" "$tmp/bin/qrencode"

export QR_PAYLOAD_FILE="$tmp/payload"
output=$(PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-network-qr" wlan0)
expected=$'100\n010\n001'
[[ $output == "$expected" ]] || fail "network QR helper emits a compact module matrix" "expected: $expected\nactual: $output"
pass "network QR helper emits a compact module matrix"

payload=$(<"$QR_PAYLOAD_FILE")
expected_payload='WIFI:T:WPA;S:Cafe\;Guest\\5G;P:p\,a\:ss\;word\\42;;'
[[ $payload == "$expected_payload" ]] || fail "network QR helper escapes Wi-Fi credentials" "expected: $expected_payload\nactual: $payload"
pass "network QR helper escapes Wi-Fi credentials"
