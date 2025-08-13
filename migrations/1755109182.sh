echo "Reset DNS configuration to DHCP (remove forced Cloudflare DNS)"

# Reset DNS to use DHCP by default instead of forcing Cloudflare
# This preserves local development environments (.local domains, etc.)
# Users can still opt-in to Cloudflare DNS using: omarchy-setup-dns cloudflare

if [ -f /etc/systemd/resolved.conf ]; then
  # Backup current config if not already backed up
  if [ ! -f /etc/systemd/resolved.conf.omarchy-backup ]; then
    sudo cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.omarchy-backup
  fi
  
  # Remove explicit DNS entries to use DHCP
  sudo sed -i '/^DNS=/d' /etc/systemd/resolved.conf
  sudo sed -i '/^FallbackDNS=/d' /etc/systemd/resolved.conf
  
  # Add empty DNS entries to ensure DHCP is used
  echo "DNS=" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
  echo "FallbackDNS=" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
  
  # Remove any forced DNS config from systemd-networkd
  if [ -f /etc/systemd/network/99-omarchy-dns.network ]; then
    sudo rm -f /etc/systemd/network/99-omarchy-dns.network
    sudo systemctl restart systemd-networkd
  fi
  
  # Restart systemd-resolved to apply changes
  sudo systemctl restart systemd-resolved
  
  echo "DNS configuration reset to use DHCP (router DNS)"
  echo "To use Cloudflare DNS, run: omarchy-setup-dns cloudflare"
fi