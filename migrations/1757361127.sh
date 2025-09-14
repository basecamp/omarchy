echo "Fix DHCP DNS to allow VPN DNS override"

if [ -f /etc/systemd/resolved.conf ]; then
  if grep -q "^DNS=$" /etc/systemd/resolved.conf && grep -q "^FallbackDNS=$" /etc/systemd/resolved.conf; then
    sudo sed -i '/^DNS=$/d; /^FallbackDNS=$/d' /etc/systemd/resolved.conf
    sudo systemctl restart systemd-resolved
  fi
fi