#!/bin/bash
set -e

echo "Setting up ghost display fix for MST devices..."

SCRIPT="$HOME/.config/hypr/fix-ghost-displays.sh"
AUTOSTART="$HOME/.config/hypr/autostart.conf"

# Copy the user Hyprland script
mkdir -p "$(dirname "$SCRIPT")"
cp "$OMARCHY_PATH/default/thunderbolt/ghost-fix/fix-ghost-displays.sh" "$SCRIPT"
chmod +x "$SCRIPT"

# Add to Hyprland autostart
mkdir -p "$(dirname "$AUTOSTART")"
touch "$AUTOSTART"
grep -q "fix-ghost-displays.sh" "$AUTOSTART" || echo "exec-once = ~/.config/hypr/fix-ghost-displays.sh" >> "$AUTOSTART"

# Install system components for hot-plug support
sudo cp "$OMARCHY_PATH/default/thunderbolt/ghost-fix/thunderbolt-ghost-fix" /usr/local/bin/
sudo chmod +x /usr/local/bin/thunderbolt-ghost-fix

sudo cp "$OMARCHY_PATH/default/thunderbolt/ghost-fix/99-thunderbolt-ghost-fix.rules" /etc/udev/rules.d/
sudo udevadm control --reload