#!/bin/bash

# Install iwd explicitly if it wasn't included in archinstall
# This can happen if archinstall used ethernet
if ! command -v iwctl &>/dev/null; then
  sudo pacman -S --noconfirm --needed iwd
  chrootable_systemctl_enable iwd.service
fi

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Ensure systemd-resolved is enabled
sudo systemctl enable --now systemd-resolved
