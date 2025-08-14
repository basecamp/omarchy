#!/bin/bash

# Install and setup snapper for Btrfs snapshot management

# Install snapper package
yay -S --noconfirm --needed snapper

# Setup snapper configurations for snapshot management
omarchy-snapshot setup || true
