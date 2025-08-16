#!/bin/bash

# Install snapper for snapshot management
if ! pacman -Q snapper &>/dev/null; then
  echo "Installing snapper for snapshot management..."
  sudo pacman -S --noconfirm snapper
fi

# Setup snapper configurations
echo "Setting up snapper configurations..."
sudo omarchy-snapshot setup || true
