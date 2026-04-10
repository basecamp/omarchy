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
if pacman -Q nodejs &>/dev/null; then
  echo "Removing nodejs (conflicts with nodejs-lts-jod required by signal-desktop-beta)..."
  sudo pacman -Rdd --noconfirm nodejs 2>/dev/null || true
fi

# Pre-install official repo dependencies that signal-desktop-beta needs
# (must happen after nodejs removal so nodejs-lts-jod doesn't conflict)
echo "Installing official dependencies for signal-desktop-beta..."
sudo pacman -S --needed --noconfirm nodejs-lts-jod pnpm libxcrypt-compat

# Pre-install AUR dependencies that makepkg can't resolve via pacman:
# - fpm: Ruby-based packaging tool (plus its ruby deps: ruby-arr-pm, ruby-clamp, etc.)
echo "Installing AUR dependencies for signal-desktop-beta..."
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" fpm

# Install signal-desktop-beta (all deps should now be satisfied)
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" signal-desktop-beta

echo "signal-desktop-beta installation complete!"
