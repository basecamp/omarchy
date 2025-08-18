#!/bin/bash

# Install iwd explicitly if it wasn't included in archinstall
# This can happen if archinstall used ethernet
if ! command -v iwctl &>/dev/null; then
  yay -S --noconfirm --needed iwd
  if is_chroot; then
    echo "⚠️  [CHROOT] Enabling iwd.service (without --now flag)"
    sudo systemctl enable iwd.service
  else
    sudo systemctl enable --now iwd.service
  fi
fi

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
