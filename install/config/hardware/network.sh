# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Set up default iwd configuration to prevent DNS conflicts and micro-drops
sudo mkdir -p /etc/iwd
if [[ ! -f /etc/iwd/main.conf ]]; then
  sudo cp "$OMARCHY_PATH/default/iwd/main.conf" /etc/iwd/main.conf
fi

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
