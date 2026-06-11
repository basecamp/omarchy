echo "Load Bluetooth driver module on T2 Macs"

if lspci -nn | grep -q "106b:180[12]"; then
  if ! grep -q "hci_bcm4377" /etc/modules-load.d/t2.conf 2>/dev/null; then
    echo "hci_bcm4377" | sudo tee -a /etc/modules-load.d/t2.conf >/dev/null
  fi
fi
