OMARCHY_DESCRIPTION="Disable power button"

omarchy_install() {
  # Disable shutting system down on power button to bind it to power menu afterwards
  sudo sed -i 's/.*HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf
}

omarchy_verify() {
  [[ -f /etc/systemd/logind.conf ]] || add_error "Logind config missing"

  # Check if power button is set to ignore
  if [[ -f /etc/systemd/logind.conf ]]; then
      grep -q "^HandlePowerKey=ignore" /etc/systemd/logind.conf || add_error "Power button not set to ignore"
  fi
}
