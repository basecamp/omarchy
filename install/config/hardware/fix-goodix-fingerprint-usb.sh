# Fix Goodix fingerprint reader (27c6:609c) disconnecting when USB devices are plugged in.
# Forces USB power control to always-on for the device, preventing conflicts with
# USB power delivery negotiation from other devices (e.g. phones).
if grep -rq "27c6" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
  if [[ ! -f /etc/udev/rules.d/99-fix-goodix-fingerprint-usb.rules ]]; then
    sudo cp "$OMARCHY_PATH/default/udev/fix-goodix-fingerprint-usb.rules" /etc/udev/rules.d/99-fix-goodix-fingerprint-usb.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
  fi
fi
