#!/bin/bash

echo "Migrating from wofi to fuzzel..."

# Install fuzzel and remove wofi
if command -v yay >/dev/null 2>&1; then
    echo "Installing fuzzel..."
    yay -S --noconfirm fuzzel
    echo "Removing wofi..."
    yay -R --noconfirm wofi 2>/dev/null || true
elif command -v pacman >/dev/null 2>&1; then
    echo "Installing fuzzel..."
    sudo pacman -S --noconfirm fuzzel
    echo "Removing wofi..."
    sudo pacman -R --noconfirm wofi 2>/dev/null || true
else
    echo "Warning: Could not find package manager. Please manually install fuzzel and remove wofi."
fi

# Create fuzzel config directory
mkdir -p ~/.config/fuzzel

# Copy fuzzel configs
echo "Setting up fuzzel configuration..."
cp -f ~/.local/share/omarchy/config/fuzzel/fuzzel.ini ~/.config/fuzzel/ 2>/dev/null
cp -f ~/.local/share/omarchy/config/fuzzel/select.ini ~/.config/fuzzel/ 2>/dev/null

# Remove old wofi configs
echo "Cleaning up wofi configuration..."
rm -rf ~/.config/wofi 2>/dev/null || true

echo "Migration to fuzzel completed successfully!"
echo "Note: If you have any custom wofi configurations, you'll need to recreate them for fuzzel."