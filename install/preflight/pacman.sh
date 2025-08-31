#!/bin/bash

# Install build tools
sudo pacman -S --needed --noconfirm base-devel

# Add fun and color and verbosity to the pacman installer
if ! grep -q "ILoveCandy" /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a Color\nILoveCandy\nVerbosePkgLists' /etc/pacman.conf
fi

# Add the Omarchy repository
if ! grep -q "omarchy" /etc/pacman.conf; then
  sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/$arch
EOF
fi

# Set mirrors to global ones only
omarchy-refresh-pacman-mirrorlist

# Refresh all repos
sudo pacman -Syu --noconfirm

