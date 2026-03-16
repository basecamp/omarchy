# Install Wi-Fi drivers for Broadcom chips found in some MacBooks, as well as other systems:
# - BCM4360 (2013–2015 MacBooks)
# - BCM4331 (2012, early 2013 MacBooks)
# - BCM43602 (MacBook Pro late 2015)

pci_info=$(lspci -nnv)

if (echo "$pci_info" | grep -q "14e4:43a0" || echo "$pci_info" | grep -q "14e4:4331"); then
  echo "BCM4360 / BCM4331 detected"
  omarchy-pkg-add broadcom-wl dkms linux-headers
fi

# Handle BCM43602 with kernel parameter fix for MacBook Pro late 2015
if echo "$pci_info" | grep -q "14e4:43a2"; then
  echo "BCM43602 detected"

  # Add modprobe configuration to disable problematic feature
  cat <<EOF | sudo tee /etc/modprobe.d/brcmfmac-bcm43602.conf >/dev/null
# Fix for BCM43602 WiFi connectivity issues on MacBook Pro late 2015
options brcmfmac feature_disable=0x82000
EOF

  # Add kernel command line parameter for bootloader
  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/bcm43602-wifi.conf >/dev/null
# BCM43602 WiFi fix for MacBook Pro late 2015
KERNEL_CMDLINE[default]+=" brcmfmac.feature_disable=0x82000"
EOF

  # Also append to /etc/default/limine if it exists, since it overrides drop-in configs
  if [ -f /etc/default/limine ] && ! grep -q 'brcmfmac.feature_disable' /etc/default/limine; then
    echo 'KERNEL_CMDLINE[default]+=" brcmfmac.feature_disable=0x82000"' | sudo tee -a /etc/default/limine >/dev/null
  fi

  echo "BCM43602 WiFi fix applied. Please run 'limine-update' and reboot for changes to take effect."
fi
