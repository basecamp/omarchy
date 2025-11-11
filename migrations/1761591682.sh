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
if ! systemctl is-enabled wpa_supplicant.service | grep -q "masked"; then
    sudo systemctl mask --now wpa_supplicant.service
fi

# Mask systemd-networkd and its sockets to prevent it from being started
if ! systemctl is-enabled systemd-networkd.socket | grep -q "masked"; then
    sudo systemctl mask --now systemd-networkd.socket
fi

if ! systemctl is-enabled systemd-networkd-varlink.socket | grep -q "masked"; then
    sudo systemctl mask --now systemd-networkd-varlink.socket
fi

if ! systemctl is-enabled systemd-networkd.service | grep -q "masked"; then
    sudo systemctl mask --now systemd-networkd.service
fi

# Make sure iwd is enabled
if ! systemctl is-enabled iwd.service | grep -q "enabled"; then
    sudo systemctl unmask iwd.service
    sudo systemctl enable --now iwd.service
fi

# Enable and start NetworkManager
if ! systemctl is-enabled NetworkManager.service | grep -q "enabled"; then
    sudo systemctl unmask NetworkManager.service
    sudo systemctl enable --now NetworkManager.service
fi

# Make sure systemd-resolved is enabled
if ! systemctl is-enabled systemd-resolved.service | grep -q "enabled"; then
    sudo systemctl unmask systemd-resolved.service
    sudo systemctl enable --now systemd-resolved.service
fi

# Restart systemd-resolved just to be sure
sudo systemctl restart systemd-resolved.service

# Prevent NetworkManager-wait-online timeout on boot
if ! systemctl is-enabled NetworkManager-wait-online.service | grep -q "masked"; then
    sudo systemctl mask --now NetworkManager-wait-online.service
fi
