#!/bin/bash

echo "Starting migration to convert Chromium webapps to Omarchy webapps."
DESKTOP_DIR="$HOME/.local/share/applications/"
FIND_STRING="Exec=chromium --new-window --ozone-platform=wayland --app="
REPLACE_STRING="Exec=omarchy-launch-webapp --app="
find "$DESKTOP_DIR" -type f -name "*.desktop" -print0 | while IFS= read -r -d \0' file; do
    if grep -q "^$FIND_STRING" "$file"; then
        sed -i "s/$FIND_STRING/$REPLACE_STRING/" "$file"
        echo "Modified: $file"
    fi
done

echo "Updating Hyprland bindings"
HYPR_BINDINGS_FILE="$HOME/.config/hypr/bindings.conf"
if [ -f "$HYPR_BINDINGS_FILE" ]; then
    sed -i 's/\$browser =.*chromium.*$/\$browser = omarchy-launch-browser/' "$HYPR_BINDINGS_FILE"
    sed -i 's/\$webapp = \$browser --app.*$/webapp = omarchy-launch-webapp --app/' "$HYPR_BINDINGS_FILE"
    echo "Hyprland bindings updated."
else
    echo "Hyprland bindings file not found at $HYPR_BINDINGS_FILE"
fi