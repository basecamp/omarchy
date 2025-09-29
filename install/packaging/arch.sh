#!/bin/bash

# Architecture-specific package installation

# Check if running on ARM architecture
if [ -n "$OMARCHY_ARM" ]; then
  echo "Installing ARM-specific packages..."

  # Install any ARM-specific packages from the packages file using yay
  if [ -s "$OMARCHY_INSTALL/omarchy-arm.packages" ]; then
    mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-arm.packages" | grep -v '^$')
    if [ ${#packages[@]} -gt 0 ]; then
      yay -S --noconfirm --needed "${packages[@]}"
    fi
  fi
else
  echo "Installing x86_64-specific packages..."

  # Install x86-specific packages using pacman with omarchy mirror
  mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-x86.packages" | grep -v '^$')
  if [ ${#packages[@]} -gt 0 ]; then
    sudo pacman -S --noconfirm --needed "${packages[@]}"
  fi
fi
