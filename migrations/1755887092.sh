#!/bin/bash

echo "Enable font rendering optimizations for high-DPI displays"

# Check if xmlstarlet is installed (needed for preserving font families)
if ! command -v xmlstarlet >/dev/null 2>&1; then
    echo "  Installing xmlstarlet for font configuration management..."
    yay -S --noconfirm xmlstarlet
fi

# Run font optimization
if [ -x "$HOME/.local/share/omarchy/bin/omarchy-font-optimize" ]; then
    "$HOME/.local/share/omarchy/bin/omarchy-font-optimize"
else
    echo "  Warning: omarchy-font-optimize not found, skipping optimization"
fi

# Enable system-wide RGB subpixel rendering if not already enabled
SUBPIXEL_LINK="/etc/fonts/conf.d/10-sub-pixel-rgb.conf"
SUBPIXEL_SOURCE="/usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf"

if [ ! -L "$SUBPIXEL_LINK" ] && [ -f "$SUBPIXEL_SOURCE" ]; then
    echo "  Enabling system-wide RGB subpixel rendering..."
    sudo ln -sf "$SUBPIXEL_SOURCE" "$SUBPIXEL_LINK" 2>/dev/null && \
        echo "  ✓ RGB subpixel rendering enabled" || \
        echo "  ! Could not enable subpixel rendering (needs sudo)"
fi