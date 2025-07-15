# Install iwd explicitly if it wasn't included in archinstall
# This can happen if archinstall used ethernet
if ! command -v iwd &>/dev/null; then
  yay -S --noconfirm --needed iwd
  sudo systemctl enable --now iwd.service
fi

# Fix systemd-networkd-wait-online timeout for multiple interfaces
# Wait for any interface to be online rather than all interfaces
# https://wiki.archlinux.org/title/Systemd-networkd#Multiple_interfaces_that_are_not_connected_all_the_time
sudo mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
sudo tee /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-networkd-wait-online --any
EOF
