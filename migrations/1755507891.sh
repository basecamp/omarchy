#!/bin/bash

echo "Starting migration to convert Chromium webapps to Omarchy webapps."
DESKTOP_DIR="$HOME/.local/share/applications/"
while IFS= read -r -d '' file; do
    if grep -q "Exec=chromium --app=" "$file"; then
        echo "Found Chromium webapp: $file"

        # Extract the URL from the Exec line
        URL=$(grep -oP '(?<=--app=)[^ ]+' "$file")
        # Extract the Name from the Name line
        NAME=$(grep -oP '(?<=^Name=).*' "$file")

        if [[ -n "$URL" && -n "$NAME" ]]; then
            echo "  Name: $NAME"
            echo "  URL: $URL"
            # Replace the Exec line to use omarchy-webapp
            sed -i "s|^Exec=chromium --app=.*|Exec=omarchy-webapp \"$NAME\" \"$URL\"|" "$file"
            echo "  Successfully migrated $file"
        else
            echo "  Could not extract Name or URL from $file. Skipping."
        fi
    fi
done < <(find "$DESKTOP_DIR" -name '*.desktop' -print0)

echo "Updating Hyprland bindings"
HYPR_BINDINGS_FILE="$HOME/.config/hypr/bindings.conf"
if [ -f "$HYPR_BINDINGS_FILE" ]; then
    sed -i 's/$browser = chromium/$browser = omarchy-browser/' "$HYPR_BINDINGS_FILE"
    sed -i 's/$webapp = chromium --app/$webapp = omarchy-webapp --app/' "$HYPR_BINDINGS_FILE"
    echo "Hyprland bindings updated."
else
    echo "Hyprland bindings file not found at $HYPR_BINDINGS_FILE"
fi