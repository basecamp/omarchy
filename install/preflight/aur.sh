#!/bin/bash

chaotic_ok=0

# Only add Chaotic-AUR if the architecture is x86_64 so ARM users can build the packages
if [[ "$(uname -m)" == "x86_64" ]]; then
  # Try installing Chaotic-AUR keyring and mirrorlist
  if sudo pacman-key --recv-key 3056513887B78AEB &&
    sudo pacman-key --lsign-key 3056513887B78AEB &&
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' &&
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then

    # Add Chaotic-AUR repo to pacman config
    echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf >/dev/null

    # Refresh pacman package databases
    sudo pacman -Sy

    chaotic_ok=1
  else
    echo "Failed to install Chaotic-AUR, so won't include it in pacman config!"
  fi
fi

if [[ $chaotic_ok -eq 1 ]]; then
  sudo pacman -S --needed --noconfirm yay
else
  # Manually install yay from AUR if not already available
  if ! command -v yay &>/dev/null; then
    # Install build tools
    sudo pacman -S --needed --noconfirm base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    cd -
    rm -rf yay-bin
    cd ~
  fi
fi

# Add fun and color to the pacman installer
sudo sed -i '/^\[options\]/a Color\nILoveCandy' /etc/pacman.conf
