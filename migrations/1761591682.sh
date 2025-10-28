#!/usr/bin/env bash
echo "Configure and enable NetworkManager, disable systemd-networkd"

# Copy Omarchy NetworkManager configuration to /etc/NetworkManager/conf.d
conf_dir="/etc/NetworkManager/conf.d"
sudo cp -f ~/.local/share/omarchy/default/networkmanager/omarchy_networkmanager.conf "$conf_dir/omarchy_networkmanager.conf"

# Check for other .conf files in and warn the user
other_files=$(find "$conf_dir" -maxdepth 1 -type f -name "*.conf" \
    ! -name "omarchy_networkmanager.conf")

if [ -n "$other_files" ]; then
    echo "WARNING: There are other configuration files in $conf_dir that might override Omarchy configuration:"
    echo "$other_files"
fi

# Mask WPA Supplicant to prevent it from being started by NetworkManager
sudo systemctl mask --now wpa_supplicant.service

# Mask systemd-networkd and its sockets to prevent it from being started
sudo systemctl mask --now systemd-networkd.socket
sudo systemctl mask --now systemd-networkd-varlink.socket
sudo systemctl mask --now systemd-networkd.service

# Enable and start NetworkManager
sudo systemctl enable --now NetworkManager.service

# Restart systemd-resolved just to be sure
sudo systemctl restart systemd-resolved.service

# Prevent NetworkManager-wait-online timeout on boot
sudo systemctl mask --now NetworkManager-wait-online.service
