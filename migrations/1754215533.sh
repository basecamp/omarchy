echo "Enable auto-discovery of network printers"

if [[ ! -f /etc/systemd/resolved.conf.d/10-disable-multicast.conf ]]; then
  omarchy-pkg-add avahi nss-mdns

  # Disable multicast dns in resolved. Avahi will provide this for better network printer discovery
  sudo mkdir -p /etc/systemd/resolved.conf.d
  echo "[Resolve]\nMulticastDNS=no" | sudo tee /etc/systemd/resolved.conf.d/10-disable-multicast.conf
  sudo systemctl enable --now avahi-daemon.service
fi

if ! grep -q '^CreateRemotePrinters Yes' /etc/cups/cups-browsed.conf; then
  omarchy-pkg-add cups-browsed
  # Enable automatically adding remote printers
  echo 'CreateRemotePrinters Yes' | sudo tee -a /etc/cups/cups-browsed.conf
  sudo systemctl enable --now cups-browsed.service
fi
