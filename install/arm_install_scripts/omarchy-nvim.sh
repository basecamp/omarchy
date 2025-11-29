#!/bin/bash

# Install omarchy-nvim from source for ARM
echo "Installing omarchy-nvim from source for ARM..."

# Check if omarchy-nvim is already installed
if command -v omarchy-nvim-setup &>/dev/null; then
  echo "omarchy-nvim already installed, skipping"
  return 0
fi

# Install dependencies
echo "Installing build dependencies..."

# Remove nodejs-lts-jod if present (signal-desktop-beta build dependency)
# We need current nodejs for development, not LTS
sudo pacman -Rdd --noconfirm nodejs-lts-jod 2>/dev/null || true

sudo pacman -S --needed --noconfirm neovim git nodejs npm tree-sitter-cli base-devel

# Clone the omarchy-pkgs repository
echo "Cloning omarchy-pkgs repository..."
cd /tmp
rm -rf omarchy-pkgs

# Try to clone with retry logic
clone_attempts=0
max_clone_attempts=3
while [ $clone_attempts -lt $max_clone_attempts ]; do
  if git clone https://github.com/omacom-io/omarchy-pkgs.git 2>&1; then
    break
  fi
  clone_attempts=$((clone_attempts + 1))
  if [ $clone_attempts -lt $max_clone_attempts ]; then
    echo "Clone failed (attempt $clone_attempts/$max_clone_attempts), retrying in 5 seconds..."
    sleep 5
  else
    echo "Failed to clone omarchy-pkgs after $max_clone_attempts attempts"
    exit 1
  fi
done

# Build and install the package
echo "Building and installing omarchy-nvim (this may take a while)..."
cd omarchy-pkgs/pkgbuilds/omarchy-nvim
makepkg -si --noconfirm

cd ~

echo "omarchy-nvim installed successfully"
echo "Run 'omarchy-nvim-setup' to configure Neovim"
