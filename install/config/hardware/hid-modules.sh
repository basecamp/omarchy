if [[ ! -f /etc/mkinitcpio.conf.d/early-hid-modules.conf ]]; then
  echo "MODULES=(xhci_pci usbhid hid_generic hid_apple)" | sudo tee /etc/mkinitcpio.conf.d/early-hid-modules.conf
fi
