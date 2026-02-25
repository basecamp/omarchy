# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Configure NetworkManager to use iwd as the WiFi backend
# This ensures NetworkManager recognizes WiFi connections managed by iwd
sudo mkdir -p /etc/NetworkManager/conf.d
echo '[device]
wifi.backend=iwd' | sudo tee /etc/NetworkManager/conf.d/iwd.conf >/dev/null

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
