#!/bin/bash

# Fix for Broadcom BCM4360 WiFi on MacBooks
# The BCM4360 chip family (PCI IDs 14e4:43a0, 14e4:43ba) has problematic 
# firmware features that cause connection failures with "Operation failed" errors in iwctl.
# This fix disables those features to restore WiFi functionality.
# See: https://github.com/basecamp/omarchy/issues/1022

# Only apply if a BCM4360 variant is detected AND the module exists
# Known affected chips: 14e4:43a0, 14e4:43ba (add more as discovered)
if lspci -nn 2>/dev/null | grep -qE "14e4:(43a0|43ba)" && modinfo brcmfmac &>/dev/null; then
  echo "Detected Broadcom BCM4360 WiFi chip, applying compatibility fix..."
  echo "options brcmfmac feature_disable=0x82000" | sudo tee /etc/modprobe.d/broadcom-macbook-wifi.conf >/dev/null
fi
