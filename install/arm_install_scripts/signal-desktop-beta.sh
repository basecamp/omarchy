#!/bin/bash
#
# Install signal-desktop-beta from AUR for ARM
# Requires nodejs-lts-jod which conflicts with current nodejs
# Remove nodejs temporarily to allow installation
#

set -euo pipefail

echo "Installing signal-desktop-beta from AUR..."

# Install git-lfs (required for signal-desktop-beta build as of Dec 2025)
if ! pacman -Q git-lfs &>/dev/null; then
  echo "Installing git-lfs (required for signal-desktop-beta build)..."
  sudo pacman -S --needed --noconfirm git-lfs
fi

# Reset Git LFS configuration to fix common build issues
echo "Configuring Git LFS (fixing common build issues)..."
# Uninstall any broken Git LFS config
git lfs uninstall 2>/dev/null || true
# Ensure proper Git config file exists
touch ~/.gitconfig
# Clear any problematic LFS config
git config --global --unset-all filter.lfs.clean 2>/dev/null || true
git config --global --unset-all filter.lfs.smudge 2>/dev/null || true
git config --global --unset-all filter.lfs.process 2>/dev/null || true
git config --global --unset-all filter.lfs.required 2>/dev/null || true
# Reinstall Git LFS with fresh config
git lfs install --force

# Remove nodejs if present (conflicts with nodejs-lts-jod required by signal-desktop-beta)
# We'll let signal-desktop-beta install nodejs-lts-jod as its dependency
if pacman -Q nodejs &>/dev/null; then
  echo "Removing nodejs (conflicts with nodejs-lts-jod required by signal-desktop-beta)..."
  sudo pacman -Rdd --noconfirm nodejs 2>/dev/null || true
fi

# Install signal-desktop-beta (will pull in nodejs-lts-jod as dependency)
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" signal-desktop-beta

echo "signal-desktop-beta installation complete!"
