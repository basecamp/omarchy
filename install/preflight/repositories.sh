#!/bin/bash

# Install build tools
sudo pacman -S --needed --noconfirm base-devel

# Add fun and color and verbosity to the pacman installer
if ! grep -q "ILoveCandy" /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a Color\nILoveCandy\nVerbosePkgLists' /etc/pacman.conf
fi

# Add the Omarchy repository
if ! grep -q "omarchy" /etc/pacman.conf; then
  echo -e "\n[omarchy]\nSigLevel = Optional TrustAll\nServer = https://pkgs.omarchy.org/\$arch/\n" | sudo tee -a /etc/pacman.conf >/dev/null
fi

# Set mirrors to global ones only
echo -e "Server = https://mirror.omarchy.org/\$repo/os/\$arch\nServer = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch\nServer = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" |
  sudo tee /etc/pacman.d/mirrorlist >/dev/null

# Refresh all repos
sudo pacman -Syu --noconfirm
