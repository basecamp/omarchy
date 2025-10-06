OMARCHY_DESCRIPTION="Printer Config"

omarchy_install() {
  chrootable_systemctl_enable cups.service

  # Disable multicast dns in resolved. Avahi will provide this for better network printer discovery
  sudo mkdir -p /etc/systemd/resolved.conf.d
  echo -e "[Resolve]\nMulticastDNS=no" | sudo tee /etc/systemd/resolved.conf.d/10-disable-multicast.conf
  chrootable_systemctl_enable avahi-daemon.service

  # Enable mDNS resolution for .local domains
  sudo sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' /etc/nsswitch.conf

  # Enable automatically adding remote printers
  if ! grep -q '^CreateRemotePrinters Yes' /etc/cups/cups-browsed.conf; then
      echo 'CreateRemotePrinters Yes' | sudo tee -a /etc/cups/cups-browsed.conf
  fi

  chrootable_systemctl_enable cups-browsed.service
}

omarchy_verify() {
  systemctl is-enabled cups.service >/dev/null 2>&1 || add_error "CUPS service not enabled"
  systemctl is-enabled avahi-daemon.service >/dev/null 2>&1 || add_error "Avahi daemon not enabled"
  systemctl is-enabled cups-browsed.service >/dev/null 2>&1 || add_error "CUPS browsed service not enabled"

  [[ -f /etc/systemd/resolved.conf.d/10-disable-multicast.conf ]] || add_error "Multicast DNS config missing"

  grep -q "mdns_minimal" /etc/nsswitch.conf || add_error "mDNS not configured in nsswitch.conf"

  [[ -f /etc/cups/cups-browsed.conf ]] && grep -q '^CreateRemotePrinters Yes' /etc/cups/cups-browsed.conf || add_error "Remote printers not enabled in CUPS"
}
