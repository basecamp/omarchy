#!/usr/bin/env bash

# Path to your Hyprland keybinds
KEYBINDS_FILE="$HOME/.config/hypr/config/keybinds.conf"

# Check if the file exists
if [[ ! -f "$KEYBINDS_FILE" ]]; then
    notify-send "Keybinds file not found!" "$KEYBINDS_FILE"
    exit 1
fi

# Parse and clean keybinds to minimal format with real command shown
keybinds=$(grep -E '^\s*bind[d]?\s*=' "$KEYBINDS_FILE" | sed -E 's/^\s*bind[d]?\s*=\s*//' | awk -F, '{
    # Trim whitespace
    for (i=1; i<=NF; i++) gsub(/^ +| +$/, "", $i)

    key = $1
    combo = $2
    action = $3
    command = $4

    # If the action is "exec", show the command
    if (action == "exec" && command != "") {
        desc = command
    } else {
        desc = action
    }

    # Replace $mainMod with SUPER
    gsub(/\$mainMod/, "SUPER", key)
    gsub(/\$mainMod/, "SUPER", combo)

    # If command or action starts with $, strip it for display
    gsub(/^\$/, "", desc)

    print key" + " combo "     " desc
}')

# Launch rofi
selected=$(echo "$keybinds" | rofi -dmenu -i -p "Hypr Keybinds" -theme ~/.config/hypr/rofi/keybinds.rasi)

# If selected, notify and copy
if [[ -n "$selected" ]]; then
    notify-send "Hypr Keybind" "$selected"
    echo "$selected" | wl-copy 2>/dev/null || echo "$selected" | xclip -selection clipboard
fi
