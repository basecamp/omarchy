#!/bin/bash
# Hyprland Visual Mode Toggle Script (comment/uncomment only)

CONFIG_DIR="$HOME/.config/hypr"
MAIN_CONFIG="$CONFIG_DIR/hyprland.conf"
MODE_CONFIG="~/.config/hypr/mode/mode.conf"

# Check if the source line exists (commented or uncommented)
MODE_LINE=$(grep -E "^\s*#?\s*source\s*=\s*~/.config/hypr/mode/mode.conf" "$MAIN_CONFIG")

if [ -z "$MODE_LINE" ]; then
    # Line not found → append uncommented
    [ -n "$(tail -c1 "$MAIN_CONFIG")" ] && echo "" >> "$MAIN_CONFIG"
    echo "source = $MODE_CONFIG" >> "$MAIN_CONFIG"
    notify-send -u normal -t 2500 -i display "Visual Mode: ON" "File: $MODE_CONFIG\nMinimal visuals enabled"
elif [[ "$MODE_LINE" =~ ^\s*# ]]; then
    # Line is commented → uncomment it
    sed -i "s|^\s*#\s*\(source\s*=\s*~/.config/hypr/mode/mode.conf\)|\1|" "$MAIN_CONFIG"
    notify-send -u normal -t 2500 -i display "Visual Mode: ON" "File: $MODE_CONFIG\nMinimal visuals enabled"
else
    # Line is uncommented → comment it
    sed -i "s|^\s*\(source\s*=\s*~/.config/hypr/mode/mode.conf\)|# \1|" "$MAIN_CONFIG"
    notify-send -u low -t 2500 -i user-offline "Visual Mode: OFF" "File: $MODE_CONFIG\nReverted to default visuals"
fi

hyprctl reload
