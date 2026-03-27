#!/usr/bin/env bash

# Fix Goodix fingerprint reader (27c6:609c) disconnecting when USB devices are plugged in.
# Forces USB power control to always-on for the device, preventing conflicts with
# USB power delivery negotiation from other devices (e.g. phones).
goodix_609c_found=0
for dev in /sys/bus/usb/devices/*; do
  if [[ -f "$dev/idVendor" && -f "$dev/idProduct" ]]; then
    if [[ "$(cat "$dev/idVendor")" == "27c6" && "$(cat "$dev/idProduct")" == "609c" ]]; then
      goodix_609c_found=1
      break
    fi
  fi
done

if [[ "${goodix_609c_found}" -eq 1 ]]; then
  if [[ ! -f /etc/udev/rules.d/99-fix-goodix-fingerprint-usb.rules ]]; then
    sudo cp "$OMARCHY_PATH/default/udev/fix-goodix-fingerprint-usb.rules" /etc/udev/rules.d/99-fix-goodix-fingerprint-usb.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=27c6 --attr-match=idProduct=609c
  fi
fi
