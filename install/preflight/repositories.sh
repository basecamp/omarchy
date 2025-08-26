#!/bin/bash

# Install build tools
sudo pacman -Sy --needed --noconfirm base-devel

# Add fun and color and verbosity to the pacman installer
if ! grep -q "ILoveCandy" /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a Color\nILoveCandy\nVerbosePkgLists' /etc/pacman.conf
fi

# Add the Omarchy repository as first choice
if ! grep -q "omarchy" /etc/pacman.conf; then
  sudo sed -i '/^\[core\]/i [omarchy]\nSigLevel = Optional TrustAll\nServer = https:\/\/pkgs.omarchy.org\/$arch\n' /etc/pacman.conf
fi

# Set mirrors to global ones only
echo -e "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch\nServer = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch" |
  sudo tee /etc/pacman.d/mirrorlist >/dev/null

# Only add Chaotic-AUR if the architecture is x86_64 so ARM users can build the packages
if [[ "$(uname -m)" == "x86_64" ]] && [ -z "$DISABLE_CHAOTIC" ]; then
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

    # Refresh all repos
    sudo pacman -Sy
  else
    echo -e "Failed to install Chaotic-AUR, so won't include it in pacman config!"
  fi
fi

# Allow repository index updates without sudo
sudo tee /etc/sudoers.d/repositories >/dev/null <<EOF
$USER ALL=(ALL) NOPASSWD: /usr/bin/pacman -Sy
EOF
sudo chmod 440 /etc/sudoers.d/repositories
