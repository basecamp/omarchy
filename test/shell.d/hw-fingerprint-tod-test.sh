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
    local product=${spec#*:}
    local dev="$tmp_dir/devices/1-$index"

    mkdir -p "$dev"
    printf '%s\n' "$vendor" >"$dev/idVendor"
    printf '%s\n' "$product" >"$dev/idProduct"
    index=$((index + 1))
  done
}

hw_fingerprint_tod() {
  OMARCHY_USB_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/omarchy-hw-fingerprint-tod"
}

assert_needs_tod() {
  local description="$1"

  hw_fingerprint_tod || fail "$description"
  pass "$description"
}

assert_open_driver() {
  local description="$1"

  if hw_fingerprint_tod; then
    fail "$description"
  fi
  pass "$description"
}

write_usb_devices '27c6:530c'
assert_needs_tod "a Goodix 530c is flagged for the proprietary driver"

write_usb_devices '27c6:533c'
assert_needs_tod "a Goodix 533c is flagged for the proprietary driver"

write_usb_devices '27c6:538c'
assert_needs_tod "a Goodix 538c is flagged for the proprietary driver"

# The open goodixmoc driver covers 5840 and up, so those must not be steered
# toward the closed blob.
write_usb_devices '27c6:5840'
assert_open_driver "a Goodix 5840 stays on the open driver"

write_usb_devices '27c6:6014'
assert_open_driver "a Goodix 6014 stays on the open driver"

write_usb_devices '27c6:9999'
assert_open_driver "an unknown Goodix product is not flagged"

write_usb_devices '138a:530c'
assert_open_driver "another vendor's 530c product id is not flagged"

# Real sysfs device directories can lack attribute files; a missing vendor
# attribute must be skipped rather than misread as a non-match on another
# field.
rm -rf "$tmp_dir/devices"
mkdir -p "$tmp_dir/devices/1-0"
printf '530c\n' >"$tmp_dir/devices/1-0/idProduct"
assert_open_driver "a device missing its vendor attribute is skipped"

write_usb_devices
assert_open_driver "a machine with no USB devices is not flagged"
