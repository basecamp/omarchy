#!/bin/bash

# Walker - Application launcher for ARM
# By default, uses prebuilt binary to avoid long Rust compile time
# Set OMARCHY_BUILD_WALKER=true to build from source instead

if command -v walker &>/dev/null; then
  echo "walker already installed, skipping"
  return 0
fi

if [[ -n "${OMARCHY_BUILD_WALKER:-}" ]]; then
  # Build from source via AUR
  echo "Building walker from source (OMARCHY_BUILD_WALKER is set)..."
  "$OMARCHY_PATH/bin/omarchy-aur-install" walker
else
  # Use prebuilt binary (default)
  echo "Installing prebuilt walker for ARM64..."
  echo "(Set OMARCHY_BUILD_WALKER=true to build from source instead)"

  # Install runtime dependencies (GTK4 layer-shell application)
  sudo pacman -S --needed --noconfirm gtk4 gtk4-layer-shell

  # Install prebuilt binary
  sudo install -m 755 "$OMARCHY_INSTALL/arm_install_scripts/binaries/walker-arm64" /usr/bin/walker

  echo "walker (prebuilt) installed successfully"
fi
