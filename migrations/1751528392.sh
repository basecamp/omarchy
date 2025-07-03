#!/bin/bash

# Migration: Replace yay with paru AUR helper
echo "Migrating from yay to paru AUR helper..."

# Install paru if not already installed
if ! command -v paru &>/dev/null; then
  echo "Installing paru with yay..."
  yay -S --noconfirm --needed paru
  echo "Paru installed successfully"
else
  echo "Paru is already installed"
fi

# Remove yay if it exists (paru can handle this)
if command -v yay &>/dev/null; then
  echo "Removing yay..."
  paru -R yay --noconfirm
  echo "yay removed successfully"
fi

echo "Migration completed. You can now use paru instead of yay for AUR package management."