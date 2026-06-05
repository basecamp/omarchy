# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Enable IPv6 privacy addresses by default
sudo mkdir -p /etc/systemd/networkd.conf.d
sudo tee /etc/systemd/networkd.conf.d/10-omarchy-ipv6-privacy.conf >/dev/null <<'EOF'
[Network]
IPv6PrivacyExtensions=yes
EOF

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
