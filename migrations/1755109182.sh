echo "Reset DNS configuration to DHCP (remove forced Cloudflare DNS) if unmodified; otherwise, back up and skip modification."

# Reset DNS to use DHCP by default instead of forcing Cloudflare
# This preserves local development environments (.local domains, etc.)
# Users can still opt-in to Cloudflare DNS using: omarchy-setup-dns cloudflare

if [ -f /etc/systemd/resolved.conf ]; then
  # Calculate hash of current config
  current_hash=$(sha256sum /etc/systemd/resolved.conf | awk '{print $1}')
  # Known default hash (replace with actual hash of Omarchy's default DHCP config)
  default_conf="[Resolve]\nDNS=\nFallbackDNS=\nDNSOverTLS=no\n"
  default_hash=$(echo -e "$default_conf" | sha256sum | awk '{print $1}')

  if [ "$current_hash" = "$default_hash" ]; then
    # Safe to overwrite
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

    # Restart systemd-resolved to apply changes
    sudo systemctl restart systemd-resolved

    echo "DNS configuration reset to use DHCP (router DNS)"
    echo "To use Cloudflare DNS, run: omarchy-setup-dns Cloudflare"
  else
    # Backup and skip modification
    backup_timestamp=$(date +"%Y%m%d%H%M%S")
    sudo cp /etc/systemd/resolved.conf "/etc/systemd/resolved.conf.bak.${backup_timestamp}"
    echo "/etc/systemd/resolved.conf has been modified by the user. Migration skipped."
  fi
fi

