OMARCHY_DESCRIPTION="Enable Bluetooth Service"

omarchy_install() {
  chrootable_systemctl_enable bluetooth.service
}

omarchy_verify() {
  systemctl is-enabled bluetooth.service >/dev/null 2>&1 || add_error "Bluetooth service not enabled"
}
