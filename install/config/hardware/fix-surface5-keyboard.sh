#!/usr/bin/env bash
# Enable early Surface Laptop 5 keyboard/I²C/HID modules so the built-in keyboard works at the greeter.

set -euo pipefail

product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo '')"
sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo '')"

# Target only Surface Laptop 5
if [[ "$sys_vendor" == "Microsoft Corporation" ]] && [[ "$product_name" == "Surface Laptop 5" ]]; then
  echo "Detected Microsoft Surface Laptop 5 — enabling early keyboard modules"

  # Working module set verified on Surface Laptop 5
  echo 'MODULES=(btrfs crc-itu-t usbhid hid-generic pinctrl_tigerlake intel_lpss_pci
  8250_dw surface_gpe surface_hotplug surface_aggregator_registry
  surface_aggregator_hub surface_aggregator surface_hid_core surface_hid
  surface_kbd xhci_hcd hid_multitouch)' \
  | sudo tee /etc/mkinitcpio.conf.d/surface5_kbd_modules.conf >/dev/null
fi
