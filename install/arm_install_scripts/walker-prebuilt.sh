#!/bin/bash

# Install prebuilt walker binary for ARM64
# This avoids the long compile time by using a precompiled binary

echo "Installing prebuilt walker 0.13.26 for ARM64..."

# Remove any existing walker packages
echo "Removing any existing walker packages..."
sudo pacman -Rdd --noconfirm walker walker-bin 2>/dev/null || true
yay -Rdd --noconfirm walker walker-bin 2>/dev/null || true

# Install runtime dependencies
echo "Installing runtime dependencies..."
sudo pacman -S --needed --noconfirm gtk4 gtk4-layer-shell libvips

# Install prebuilt binary
echo "Installing prebuilt walker binary..."
sudo install -m 755 $OMARCHY_INSTALL/arm_install_scripts/binaries/walker-arm64 /usr/bin/walker

echo "Walker 0.13.26 (prebuilt) installed successfully"
