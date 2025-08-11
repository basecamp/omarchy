echo "Disable systemd-networkd-wait-online"

sudo rm -rf /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
