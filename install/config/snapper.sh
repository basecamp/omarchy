#!/bin/bash

# Install and setup snapper for Btrfs snapshot management

# Install snapper package
yay -S --noconfirm --needed snapper

# Setup snapper configurations for snapshot management
if command -v snapper &>/dev/null && command -v omarchy-snapshot &>/dev/null; then
  sudo omarchy-snapshot setup || true
fi

