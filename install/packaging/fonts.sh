#!/bin/bash

# Omarchy logo in a font for Waybar use
mkdir -p ~/.local/share/fonts
cp "$(dirname "$(dirname "$OMARCHY_INSTALL")")/config/omarchy.ttf" ~/.local/share/fonts/ 2>/dev/null || cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/ 2>/dev/null || true
fc-cache
