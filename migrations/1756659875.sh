echo "Switching from systemd-networkd to NetworkManager"

if systemctl is-enabled --quiet NetworkManager.service 2>/dev/null; then
  echo "NetworkManager is already enabled, skipping migration"
  exit 0
fi

yay -S --noconfirm --needed networkmanager

sudo systemctl disable --now systemd-networkd.service
sudo systemctl disable --now systemd-networkd-wait-online.service

if systemctl is-active --quiet wpa_supplicant.service 2>/dev/null; then
  sudo systemctl disable --now wpa_supplicant.service
fi

sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/wifi_backend.conf >/dev/null <<EOF
[device]
wifi.backend=iwd
EOF

if [[ ! -L /etc/resolv.conf ]] || ! readlink /etc/resolv.conf | grep -q "systemd/resolve"; then
  # Backup existing resolv.conf if it's a regular file
  if [[ -f /etc/resolv.conf ]] && [[ ! -L /etc/resolv.conf ]]; then
    echo "Backing up existing /etc/resolv.conf to /etc/resolv.conf.backup"
    sudo cp /etc/resolv.conf /etc/resolv.conf.backup
  fi

  # Remove existing file/symlink and create proper symlink
  sudo rm -f /etc/resolv.conf
  sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null <<EOF
[main]
dns=systemd-resolved
EOF

sudo systemctl enable --now NetworkManager.service

# Remove any custom systemd-networkd-wait-online overrides since we're not using it anymore
if [[ -f /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf ]]; then
  echo "Removing systemd-networkd-wait-online override..."
  sudo rm -f /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf
  sudo rmdir /etc/systemd/system/systemd-networkd-wait-online.service.d/ 2>/dev/null || true
fi

# Reload systemd daemon
sudo systemctl daemon-reload
