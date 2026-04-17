#!/usr/bin/env bash

# Fix Goodix fingerprint reader (27c6:609c) disconnecting when USB devices are plugged in
# and failing to resume after system suspend.
#
# Two fixes applied:
# 1. udev rule: forces power/control=on so the device never autosuspends
# 2. USB quirk RESET_RESUME (0x0080): forces a full USB reset on resume instead of
#    a soft resume which fails with -EINVAL on this device
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

  if [[ ! -f /etc/modprobe.d/fix-goodix-fingerprint-usb.conf ]]; then
    echo "options usbcore quirks=27c6:609c:0x0080" | sudo tee /etc/modprobe.d/fix-goodix-fingerprint-usb.conf > /dev/null
  fi

  if [[ ! -f /usr/lib/systemd/system-sleep/fix-goodix-fingerprint-resume ]]; then
    sudo mkdir -p /usr/lib/systemd/system-sleep
    sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/fix-goodix-fingerprint-resume" /usr/lib/systemd/system-sleep/
  fi
fi
