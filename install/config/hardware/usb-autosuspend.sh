OMARCHY_DESCRIPTION="USB Autosuspend"

omarchy_install() {
  # Disable USB autosuspend to prevent peripheral disconnection issues
  if [[ ! -f /etc/modprobe.d/disable-usb-autosuspend.conf ]]; then
    echo "options usbcore autosuspend=-1" | sudo tee /etc/modprobe.d/disable-usb-autosuspend.conf
  fi
}

omarchy_verify() {
  [[ -f /etc/modprobe.d/disable-usb-autosuspend.conf ]] || add_error "USB autosuspend config missing"

  if [[ -f /etc/modprobe.d/disable-usb-autosuspend.conf ]]; then
    grep -q "options usbcore autosuspend=-1" /etc/modprobe.d/disable-usb-autosuspend.conf || add_error "USB autosuspend not disabled"
  fi
}
