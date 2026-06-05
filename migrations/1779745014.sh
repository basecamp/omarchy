echo "Enable IPv6 privacy extensions for systemd-networkd"

if ! grep -Rqs '^[[:space:]]*IPv6PrivacyExtensions[[:space:]]*=' /etc/systemd/networkd.conf /etc/systemd/networkd.conf.d /etc/systemd/network; then
  sudo mkdir -p /etc/systemd/networkd.conf.d
  sudo tee /etc/systemd/networkd.conf.d/10-omarchy-ipv6-privacy.conf >/dev/null <<'EOF'
[Network]
IPv6PrivacyExtensions=yes
EOF
fi
