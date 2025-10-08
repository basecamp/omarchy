#!/bin/bash

# Install yay early on ARM systems (needed before base packages can be installed)
# TODO: Remove when omarchy repo adds ARM package support

if [ -n "$OMARCHY_ARM" ]; then
  if ! command -v yay &>/dev/null; then
    echo "Installing yay for ARM package management (temporary workaround)..."
    # Install build tools
    sudo pacman -S --needed --noconfirm base-devel
    # Use omarchy-aur-install with automatic AUR/GitHub fallback
    "$OMARCHY_PATH/bin/omarchy-aur-install" yay-bin
  fi
fi
