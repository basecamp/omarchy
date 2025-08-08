echo "Set default DNS to Cloudflare (backup to Google) and tune MTU probing for more reliable SSH"

# Set Cloudflare as primary DNS (with Google as backup)
sudo cp ~/.local/share/omarchy/default/systemd/resolved.conf /etc/systemd/
sudo systemctl restart systemd-resolved

# Solve common flakiness with SSH
echo "net.ipv4.tcp_mtu_probing=1" | sudo tee -a /etc/sysctl.d/99-sysctl.conf
