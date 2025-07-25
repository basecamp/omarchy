#!/bin/bash

# Only add Chaotic-AUR if the architecture is x86_64 so ARM users can build the packages
if [[ "$(uname -m)" == "x86_64" ]]; then
  # Import Chaotic-AUR key
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB

  # Install Chaotic-AUR keyring and mirrorlist
  sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
  sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

  # Add Chaotic-AUR repo to pacman config
  echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf >/dev/null

  # Refresh pacman package databases
  sudo pacman -Sy

  # Install yay
  sudo pacman -S --needed --noconfirm yay
else
  sudo pacman -S --needed --noconfirm base-devel

  if ! command -v yay &>/dev/null; then
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
