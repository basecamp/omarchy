#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Each argument is an rfkill device as "name:type". The function writes each device
# in the layout of sysfs: /sys/class/rfkill/rfkillN/{name,type}.
write_rfkill_devices() {
  rm -rf "$tmp_dir/rfkill"
  mkdir -p "$tmp_dir/rfkill"

  local index=0
  local spec
  for spec in "$@"; do
    local device="$tmp_dir/rfkill/rfkill$index"
    mkdir -p "$device"
    printf '%s\n' "${spec%%:*}" >"$device/name"
    printf '%s\n' "${spec##*:}" >"$device/type"
    index=$((index + 1))
  done
}

hw_bluetooth() {
  OMARCHY_RFKILL_PATH="$tmp_dir/rfkill" "$ROOT/bin/omarchy-hw-bluetooth"
}

assert_detects() {
  local description="$1" expected="$2"

  local actual=no
  hw_bluetooth && actual=yes

  [[ $actual == "$expected" ]] ||
    fail "$description" "omarchy-hw-bluetooth: expected $expected, got $actual"

  pass "$description"
}

# This device is the radio, on hardware where the block keeps the hci device in the
# kernel.
write_rfkill_devices "hci0:bluetooth"
assert_detects "a machine with an hci device has bluetooth hardware" yes

# Only the ThinkPad ACPI switch survives a soft block. The kernel no longer has the
# radio that this switch gates, so this entry is the only proof of the hardware.
write_rfkill_devices "tpacpi_bluetooth_sw:bluetooth"
assert_detects "a machine with only the platform switch has bluetooth hardware" yes

write_rfkill_devices "tpacpi_bluetooth_sw:bluetooth" "phy0:wlan"
assert_detects "a machine with more than one radio has bluetooth hardware" yes

write_rfkill_devices "phy0:wlan"
assert_detects "wifi alone is not bluetooth hardware" no

write_rfkill_devices
assert_detects "a machine with no radios has no bluetooth hardware" no

# A machine without rfkill in the kernel has no sysfs directory for the glob.
rm -rf "$tmp_dir/rfkill"
assert_detects "a machine with no rfkill tree has no bluetooth hardware" no
