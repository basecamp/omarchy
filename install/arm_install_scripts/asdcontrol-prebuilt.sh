#!/bin/bash

if command -v asdcontrol &>/dev/null; then
  echo "asdcontrol already installed, skipping"
  return 0
fi

# Install prebuilt asdcontrol binary for ARM64
# This avoids the long compile time by using a precompiled binary

echo "Installing prebuilt asdcontrol for ARM64..."

# Install runtime dependencies (adjust if asdcontrol has specific deps)
echo "Installing runtime dependencies..."
sudo pacman -S --needed --noconfirm base-devel

# Install prebuilt binary
echo "Installing prebuilt asdcontrol binary..."
sudo install -m 755 $OMARCHY_INSTALL/arm_install_scripts/binaries/asdcontrol-arm64 /usr/bin/asdcontrol

echo "asdcontrol (prebuilt) installed successfully"
