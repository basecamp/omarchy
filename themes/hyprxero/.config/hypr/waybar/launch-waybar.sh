#!/usr/bin/env bash
WAYBAR_CONFIG_DIR="$HOME/.config/hypr/waybar"
LAPTOP_CONFIG="$WAYBAR_CONFIG_DIR/laptop/config"
DESKTOP_CONFIG="$WAYBAR_CONFIG_DIR/config"
STYLE="$WAYBAR_CONFIG_DIR/style.css"
STYLE2="$WAYBAR_CONFIG_DIR/laptop/style.css"

echo "Checking for battery..."
ls /sys/class/power_supply/

if ls /sys/class/power_supply/ | grep -qi 'BAT0'; then
    echo "Laptop detected. Starting Waybar with laptop config."
    echo "Config: $LAPTOP_CONFIG"
    echo "Style: $STYLE2"
    waybar --config "$LAPTOP_CONFIG" --style "$STYLE2"
else
    echo "Desktop detected. Starting Waybar with desktop config."
    echo "Config: $DESKTOP_CONFIG"
    echo "Style: $STYLE"
    waybar --config "$DESKTOP_CONFIG" --style "$STYLE"
fi
