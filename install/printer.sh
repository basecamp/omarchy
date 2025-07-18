#!/bin/bash

sudo pacman -S --noconfirm cups cups-pdf cups-filters system-config-printer \
  avahi nss-mdns

sudo systemctl enable --now cups.service

# Disable multicast dns in resolved. Avahi will provide this for better network
# printer discovery
sudo mkdir -p /etc/systemd/resolved.conf.d
echo "[Resolve]\nMulticastDNS=no" | sudo tee /etc/systemd/resolved.conf.d/10-disable-multicast.conf

sudo systemctl enable --now avahi-daemon.service
