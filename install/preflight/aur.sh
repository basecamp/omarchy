#!/bin/bash

# Only add Chaotic-AUR if the architecture is x86_64 so ARM users can build the packages
if [[ "$(uname -m)" == "x86_64" ]] && [ -z "$DISABLE_CHAOTIC" ] && ! command -v yay &>/dev/null; then
  # Create state directory
  mkdir -p ~/.local/share/omarchy/state
  
  # Check for network connectivity before attempting Chaotic-AUR installation
  if ping -c1 1.1.1.1 >/dev/null 2>&1; then
    # Try installing Chaotic-AUR keyring and mirrorlist
    if ! pacman-key --list-keys 3056513887B78AEB >/dev/null 2>&1 &&
      sudo pacman-key --recv-key 3056513887B78AEB &&
      sudo pacman-key --lsign-key 3056513887B78AEB &&
      sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' &&
      sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then

      # Add Chaotic-AUR repo to pacman config
      if ! grep -q "chaotic-aur" /etc/pacman.conf; then
        echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf >/dev/null
      fi

      # Install yay directly from Chaotic-AUR
      sudo pacman -Sy --needed --noconfirm yay
      
      # Mark Chaotic-AUR as successfully installed
      touch ~/.local/share/omarchy/state/chaotic-aur-installed
    else
      echo "Failed to install Chaotic-AUR, so won't include it in pacman config!"
      # Mark for retry during next update
      touch ~/.local/share/omarchy/state/chaotic-aur-pending
    fi
  else
    echo "No network connectivity - skipping Chaotic-AUR installation"
    # Mark for retry when network becomes available
    touch ~/.local/share/omarchy/state/chaotic-aur-pending
  fi
fi

# Manually install yay from AUR if not already available
if ! command -v yay &>/dev/null; then
  # Check for network connectivity before attempting git clone
  if ping -c1 1.1.1.1 >/dev/null 2>&1; then
    # Install build tools
    sudo pacman -Sy --needed --noconfirm base-devel
    cd /tmp
    rm -rf yay-bin
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    cd -
    rm -rf yay-bin
    cd ~
  else
    echo "No network connectivity - cannot install yay from AUR"
    # Create state file to indicate yay installation is pending
    mkdir -p ~/.local/share/omarchy/state
    touch ~/.local/share/omarchy/state/yay-pending
  fi
fi

# Add fun and color to the pacman installer
if ! grep -q "ILoveCandy" /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a Color\nILoveCandy' /etc/pacman.conf
fi
