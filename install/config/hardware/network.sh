# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Deprioritize iPhone USB tethering below Wi-Fi so plugging in an iPhone
# to charge does not hijack the default route.
sudo mkdir -p /etc/systemd/network
sudo cp ~/.local/share/omarchy/default/systemd/network/15-ipheth.network /etc/systemd/network/
