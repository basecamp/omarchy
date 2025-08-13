echo "Use DNS over TLS when possible with certificate validation"

# Use DNS over TLS when possible with certificate validation
sudo cp ~/.local/share/omarchy/default/systemd/resolved.conf /etc/systemd/
sudo systemctl restart systemd-resolved
