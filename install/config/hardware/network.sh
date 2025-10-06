OMARCHY_DESCRIPTION="Network Config"

omarchy_install() {
  sudo systemctl enable iwd.service

  sudo systemctl disable systemd-networkd-wait-online.service
  sudo systemctl mask systemd-networkd-wait-online.service
}

omarchy_verify() {
  systemctl is-enabled iwd.service >/dev/null 2>&1 || add_error "IWD service not enabled"

  systemctl is-enabled systemd-networkd-wait-online.service 2>&1 | grep -q "masked" || add_error "systemd-networkd-wait-online not masked"
}
