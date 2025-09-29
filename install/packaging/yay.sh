#!/bin/bash

# Temporary: Install yay for ARM package management
# Remove this file when omarchy repo supports ARM packages

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
