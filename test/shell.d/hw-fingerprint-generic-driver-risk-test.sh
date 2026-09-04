#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

write_usb_devices() {
  rm -rf "$tmp_dir/devices"
  mkdir -p "$tmp_dir/devices"

  local index=0
  local spec
  for spec in "$@"; do
    local vendor=${spec%%:*}
    local product_id=${spec#*:}
    local dev="$tmp_dir/devices/1-$index"

    mkdir -p "$dev"
    printf '%s\n' "$vendor" >"$dev/idVendor"
    printf '%s\n' "$product_id" >"$dev/idProduct"
    index=$((index + 1))
  done
}

hw_fingerprint_generic_driver_risk() {
  OMARCHY_USB_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/omarchy-hw-fingerprint-generic-driver-risk"
}

write_usb_devices '04f3:0c4b'
output=$(hw_fingerprint_generic_driver_risk) || fail "a known-risk reader (04f3:0c4b) is flagged"
[[ $output == "04f3:0c4b" ]] || fail "a known-risk reader (04f3:0c4b) is flagged" "expected id '04f3:0c4b', got '$output'"
pass "a known-risk reader (04f3:0c4b) is flagged"

write_usb_devices '27c6:5385'
if hw_fingerprint_generic_driver_risk >/dev/null; then
  fail "an unrelated reader is not flagged"
fi
pass "an unrelated reader is not flagged"

write_usb_devices
if hw_fingerprint_generic_driver_risk >/dev/null; then
  fail "no connected devices is not flagged"
fi
pass "no connected devices is not flagged"
