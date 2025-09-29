#!/bin/bash

# Install yay early on ARM systems (needed before base packages can be installed)
# TODO: Remove when omarchy repo adds ARM package support

if [ -n "$OMARCHY_ARM" ]; then
  if ! command -v yay &>/dev/null; then
    echo "Installing yay for ARM package management (temporary workaround)..."
    # Install build tools
    sudo pacman -S --needed --noconfirm base-devel
    cd /tmp
    rm -rf yay-bin
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    cd -
    rm -rf yay-bin
    cd ~
  fi
fi
