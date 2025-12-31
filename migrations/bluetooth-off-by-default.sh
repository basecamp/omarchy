#!/bin/bash
set -e

CONF="/etc/bluetooth/main.conf"

# Ensure config file exists
sudo mkdir -p /etc/bluetooth
sudo touch "$CONF"

# Remove any existing AutoEnable lines (commented or not)
sudo sed -i '/^[#[:space:]]*AutoEnable=/d' "$CONF"

# Ensure [Policy] section exists
if ! grep -q "^\[Policy\]" "$CONF"; then
    echo -e "\n[Policy]" | sudo tee -a "$CONF" > /dev/null
fi

# Add AutoEnable=false under [Policy]
sudo sed -i '/^\[Policy\]/a AutoEnable=false' "$CONF"

# Restart Bluetooth
sudo systemctl restart bluetooth.service

echo "Bluetooth AutoEnable set to false (default power OFF)"

