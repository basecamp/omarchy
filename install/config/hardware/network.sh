# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Enable systemd-networkd to handle DHCP for iwd connections
sudo systemctl enable systemd-networkd.service

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Fix rfkill race condition on boot (WiFi soft-blocked before systemd-rfkill restores state)
# This ensures WiFi is unblocked when the interface appears, fixing issues with MediaTek MT7925 and similar
if [[ ! -f /etc/udev/rules.d/81-wifi-unblock.rules ]]; then
  echo 'ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/usr/bin/rfkill unblock wifi"' | sudo tee /etc/udev/rules.d/81-wifi-unblock.rules
fi
