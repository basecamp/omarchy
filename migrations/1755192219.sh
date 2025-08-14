#!/bin/bash

# Install snapper for snapshot management
if ! pacman -Q snapper &>/dev/null; then
  echo "Installing snapper for snapshot management..."
  sudo pacman -S --noconfirm snapper
fi

# Setup snapper configurations
if command -v snapper &>/dev/null && command -v omarchy-snapshot &>/dev/null; then
  echo "Setting up snapper configurations..."
  sudo omarchy-snapshot setup || true
fi

