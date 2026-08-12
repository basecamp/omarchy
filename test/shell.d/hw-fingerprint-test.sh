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
    local remainder=${spec#*:}
    local product_id=${remainder%%:*}
    # A spec with no third field describes a device with no product
    # descriptor. Without this guard ${remainder#*:} would return the product
    # id unchanged and quietly write it out as the product string.
    local product=""
    if [[ $remainder == *:* ]]; then
      product=${remainder#*:}
    fi
    local dev="$tmp_dir/devices/1-$index"

    mkdir -p "$dev"
    printf '%s\n' "$vendor" >"$dev/idVendor"
    printf '%s\n' "$product_id" >"$dev/idProduct"
    [[ -n $product ]] && printf '%s\n' "$product" >"$dev/product"
    index=$((index + 1))
  done
}

hw_fingerprint() {
  OMARCHY_USB_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/omarchy-hw-fingerprint"
}

assert_detects() {
  local description="$1"

  hw_fingerprint || fail "$description"
  pass "$description"
}

assert_rejects() {
  local description="$1"

  if hw_fingerprint; then
    fail "$description"
  fi
  pass "$description"
}

write_usb_devices '10a5:a305:FPC L:0000 FW:1425046'
assert_detects "an FPC reader is detected by its product string"

write_usb_devices '10a5:1234:Generic USB Device'
assert_rejects "a generic 10a5 USB device is not detected"

write_usb_devices '10a5:9800:FPC Sensor Controller L:0002 FW:25.26.23.14'
assert_detects "an FPC reader is detected by its sensor-controller string"

# Pins the match to a prefix. FPC abbreviates unrelated things too, and this
# branch is trusted with no kernel-driver check, so the token is not enough.
write_usb_devices '0bda:5842:USB2.0 FPC Camera'
assert_rejects "an FPC token mid-string is not detected"

write_usb_devices '1234:5678:Goodix Fingerprint USB Device'
assert_detects "a reader is detected by an existing product-name match"

write_usb_devices '27c6:1234'
assert_detects "a reader is detected by an existing vendor match"

bind_driver() {
  local dev="$1" driver="$2"

  # sysfs links the interface at a driver directory, and the detector's [[ -e ]]
  # follows the link, so the target has to exist for this to model anything.
  mkdir -p "$tmp_dir/drivers/$driver" "$tmp_dir/devices/$dev"
  ln -sf "$tmp_dir/drivers/$driver" "$tmp_dir/devices/$dev/driver"
}

write_usb_devices '27c6:1234'
bind_driver '1-0/1-0:1.0' uvcvideo
assert_rejects "a vendor guess bound to a kernel driver is rejected"

write_usb_devices '27c6:1234'
bind_driver '1-0/1-0:1.0' usbfs
assert_detects "a vendor guess claimed through usbfs is still detected"

write_usb_devices '27c6:1234'
bind_driver '1-0/1-0:1.0' usbfs
bind_driver '1-0/1-0:1.1' uvcvideo
assert_rejects "a real driver alongside a usbfs claim is still rejected"

# The product-name branch is trusted outright, whatever is bound to it.
write_usb_devices '27c6:1234:Goodix Fingerprint USB Device'
bind_driver '1-0/1-0:1.0' uvcvideo
assert_detects "a self-named reader is detected with a driver bound"

write_usb_devices '1234:5678:Generic USB Device'
assert_rejects "a machine with no matching USB devices detects nothing"
