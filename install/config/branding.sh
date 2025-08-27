#!/bin/bash

# Allow the user to change the branding for fastfetch and screensaver
mkdir -p ~/.config/omarchy/branding
mkdir -p ~/.local/share/omarchy

# Copy icon and logo files to both locations
cp "$(dirname "$OMARCHY_INSTALL")/../icon.txt" ~/.config/omarchy/branding/about.txt 2>/dev/null || true
cp "$(dirname "$OMARCHY_INSTALL")/../logo.txt" ~/.config/omarchy/branding/screensaver.txt 2>/dev/null || true

# Ensure logo.txt exists in ~/.local/share/omarchy/
cp "$(dirname "$OMARCHY_INSTALL")/../logo.txt" ~/.local/share/omarchy/logo.txt 2>/dev/null || true
