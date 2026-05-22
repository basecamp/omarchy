# Enable early module loading for USB/wireless HID devices at the boot screen
sudo mkdir -p /etc/mkinitcpio.conf.d
if [[ ! -f /etc/mkinitcpio.conf.d/early-hid-modules.conf ]]; then
  echo "MODULES+=(xhci_pci usbhid hid_generic hid_apple)" | sudo tee /etc/mkinitcpio.conf.d/early-hid-modules.conf
  sudo mkinitcpio -P
fi
