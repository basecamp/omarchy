# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Configure NetworkManager
sudo cp -f ~/.local/share/omarchy/default/networkmanager/omarchy_networkmanager.conf /etc/NetworkManager/conf.d/omarchy_networkmanager.conf

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Mask WPA Supplicant to prevent it from being started by NetworkManager
sudo systemctl mask --now wpa_supplicant.service

# Mask systemd-networkd and its sockets to prevent it from being started
sudo systemctl mask --now systemd-networkd.socket
sudo systemctl mask --now systemd-networkd-varlink.socket
sudo systemctl mask --now systemd-networkd.service

# Enable and start NetworkManager
sudo systemctl enable NetworkManager.service

# Prevent NetworkManager-wait-online timeout on boot
sudo systemctl mask NetworkManager-wait-online.service