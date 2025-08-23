#!/bin/bash

# Only install snapper on btrfs systems
# User should have selected this during arch config based on omarchy manual anyway
if findmnt -n -o FSTYPE / | grep -q btrfs; then
  echo "Detected btrfs filesystem - installing snapper..."

  sudo pacman -S --noconfirm --needed snapper

  # Configure snapper for root subvolume (only if not already configured)
  if ! sudo snapper -c root list-configs | grep -q "root"; then
    echo "Configuring snapper for root subvolume..."
    sudo snapper -c root create-config /
    
    # Set up reasonable defaults
    sudo snapper -c root set-config TIMELINE_CREATE=yes
    sudo snapper -c root set-config TIMELINE_CLEANUP=yes
    sudo snapper -c root set-config NUMBER_CLEANUP=yes
    sudo snapper -c root set-config NUMBER_LIMIT=10
    
    # Create initial snapshot
    sudo snapper -c root create --description "omarchy-initial-install"
  else
    echo "Snapper already configured for root - skipping configuration"
  fi

  echo -e "\e[32m[PASS]\e[0m Snapper configured and ready"
else
  echo "Non-btrfs filesystem detected - skipping snapper installation"
fi

