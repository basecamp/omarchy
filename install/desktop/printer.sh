#!/bin/bash

sudo pacman -S --noconfirm cups cups-pdf cups-filters cups-browsed system-config-printer avahi nss-mdns
if is_chroot; then
  echo "⚠️  [CHROOT] Enabling cups.service (without --now flag)"
  sudo systemctl enable cups.service
else
  sudo systemctl enable --now cups.service
fi

# Disable multicast dns in resolved. Avahi will provide this for better network printer discovery
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nMulticastDNS=no" | sudo tee /etc/systemd/resolved.conf.d/10-disable-multicast.conf
if is_chroot; then
  echo "⚠️  [CHROOT] Enabling avahi-daemon.service (without --now flag)"
  sudo systemctl enable avahi-daemon.service
else
  sudo systemctl enable --now avahi-daemon.service
fi

# Enable automatically adding remote printers
if ! grep -q '^CreateRemotePrinters Yes' /etc/cups/cups-browsed.conf; then
  echo 'CreateRemotePrinters Yes' | sudo tee -a /etc/cups/cups-browsed.conf
fi

if is_chroot; then
  echo "⚠️  [CHROOT] Enabling cups-browsed.service (without --now flag)"
  sudo systemctl enable cups-browsed.service
else
  sudo systemctl enable --now cups-browsed.service
fi
