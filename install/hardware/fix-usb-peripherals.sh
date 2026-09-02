# Ensure hotplugged USB dock/hub peripherals join the seat and can wake from suspend
if [[ ! -f /etc/udev/rules.d/60-omarchy-usb-peripherals.rules ]]; then
  sudo mkdir -p /etc/udev/rules.d
  sudo cp -f "$OMARCHY_PATH/default/udev/omarchy-usb-peripherals.rules" /etc/udev/rules.d/60-omarchy-usb-peripherals.rules
  udevadm control --reload 2>/dev/null || true
  udevadm trigger --subsystem-match=usb --subsystem-match=input 2>/dev/null || true
fi
