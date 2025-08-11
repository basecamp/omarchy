echo "Disable systemd-networkd-wait-online"
rm /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf

sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
