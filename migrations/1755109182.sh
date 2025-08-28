echo "Reset DNS configuration to DHCP (remove forced Cloudflare DNS)"

# Reset DNS to use DHCP by default instead of forcing Cloudflare
# This preserves local development environments (.local domains, etc.)
# Users can still opt-in to Cloudflare DNS using: omarchy-setup-dns cloudflare

if [ -f /etc/systemd/resolved.conf ]; then
  # Backup current config with timestamp
  backup_timestamp=$(date +"%Y%m%d%H%M%S")
  sudo cp /etc/systemd/resolved.conf "/etc/systemd/resolved.conf.bak.${backup_timestamp}"

  # Remove explicit DNS entries to use DHCP
  sudo sed -i '/^DNS=/d' /etc/systemd/resolved.conf
  sudo sed -i '/^FallbackDNS=/d' /etc/systemd/resolved.conf

  # Add empty DNS entries to ensure DHCP is used
  echo "DNS=" | sudo tee -a /etc/systemd/resolved.conf >/dev/null
  echo "FallbackDNS=" | sudo tee -a /etc/systemd/resolved.conf >/dev/null

  # Remove any forced DNS config from systemd-networkd
  if [ -f /etc/systemd/network/99-omarchy-dns.network ]; then
    sudo rm -f /etc/systemd/network/99-omarchy-dns.network
    sudo systemctl restart systemd-networkd
  fi
  
  # Remove UseDNS=no from all network files to allow DHCP DNS
  # This matches what omarchy-setup-dns DHCP does
  for file in /etc/systemd/network/*.network; do
    [[ -f "$file" ]] || continue
    sudo sed -i '/^UseDNS=no/d' "$file"
  done

  # Restart systemd services to apply changes
  sudo systemctl restart systemd-networkd systemd-resolved

  echo "DNS configuration reset to use DHCP (router DNS)"
  echo "To use Cloudflare DNS, run: omarchy-setup-dns Cloudflare"
fi

