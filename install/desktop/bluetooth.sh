#!/bin/bash

# Install bluetooth controls
yay -S --noconfirm --needed blueberry

# Turn on bluetooth by default
if is_chroot; then
  echo "⚠️  [CHROOT] Enabling bluetooth.service (without --now flag)"
  sudo systemctl enable bluetooth.service
else
  sudo systemctl enable --now bluetooth.service
fi
