#!/bin/bash
#
# Install signal-desktop-beta from AUR for ARM
# Requires nodejs-lts-jod which conflicts with current nodejs
# Remove nodejs temporarily to allow installation
#

set -euo pipefail

echo "Installing signal-desktop-beta from AUR..."

# Remove nodejs if present (conflicts with nodejs-lts-jod required by signal-desktop-beta)
# We'll let signal-desktop-beta install nodejs-lts-jod as its dependency
if pacman -Q nodejs &>/dev/null; then
  echo "Removing nodejs (conflicts with nodejs-lts-jod required by signal-desktop-beta)..."
  sudo pacman -Rdd --noconfirm nodejs 2>/dev/null || true
fi

# Install signal-desktop-beta (will pull in nodejs-lts-jod as dependency)
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" signal-desktop-beta

echo "signal-desktop-beta installation complete!"
