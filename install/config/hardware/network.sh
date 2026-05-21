# Ensure NetworkManager will be started
sudo systemctl enable NetworkManager.service
sudo systemctl disable iwd.service 2>/dev/null || true

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
