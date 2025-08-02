#!/bin/bash

# Check if Intel CPU
is_intel=false
if grep -q "vendor_id.*GenuineIntel" /proc/cpuinfo || lscpu | grep -q "Vendor ID:.*GenuineIntel"; then
  is_intel=true
fi

if [ "$is_intel" = false ]; then
  exit 0
fi

# Install bolt for Thunderbolt device authorization
if ! command -v boltctl &> /dev/null; then
  echo "Installing bolt for Intel Thunderbolt support..."
  sudo pacman -S --needed --noconfirm bolt
fi

# Install asdbctl for Apple Studio Display brightness control
if ! command -v asdbctl &> /dev/null; then
  echo "Installing asdbctl for Studio Display brightness control..."
  yay -S --needed --noconfirm asdbctl
fi