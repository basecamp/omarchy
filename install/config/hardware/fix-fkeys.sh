OMARCHY_DESCRIPTION="Set F-keys as F-keys by default"

omarchy_install() {
  # Ensure that F-keys on Apple-like keyboards (such as Lofree Flow84) are always F-keys
  if [[ ! -f /etc/modprobe.d/hid_apple.conf ]]; then
      echo "options hid_apple fnmode=2" | sudo tee /etc/modprobe.d/hid_apple.conf
  fi
}

omarchy_verify() {
  [[ -f /etc/modprobe.d/hid_apple.conf ]] || add_error "Apple HID config missing"

  if [[ -f /etc/modprobe.d/hid_apple.conf ]]; then
      grep -q "options hid_apple fnmode=2" /etc/modprobe.d/hid_apple.conf || add_error "F-key mode not configured"
  fi
}
