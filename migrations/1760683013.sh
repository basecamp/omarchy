#!/bin/bash

# Migration script to add do-not-disturb indicator to waybar

CONFIG_FILE="$HOME/.config/waybar/config.jsonc"
STYLE_FILE="$HOME/.config/waybar/style.css"

# Backup files
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
cp "$STYLE_FILE" "$STYLE_FILE.bak"

# Update modules-center to include do-not-disturb-indicator
sed -i 's/"modules-center": \["clock", "custom\/update", "custom\/screenrecording-indicator"\]/"modules-center": ["custom\/do-not-disturb-indicator","clock", "custom\/update", "custom\/screenrecording-indicator"]/' "$CONFIG_FILE"

# Add custom/do-not-disturb-indicator configuration after tray section
sed -i '/"tray": {/,/^[[:space:]]*"spacing": 12$/{
    /^[[:space:]]*"spacing": 12$/a\
  },\
  "custom/do-not-disturb-indicator": {\
    "on-click": "makoctl mode -t do-not-disturb && notify-send '\''Enabled notifications'\''",\
    "exec": "$OMARCHY_PATH/default/waybar/indicators/do-not-disturb.sh",\
    "signal": 9,\
    "return-type": "json"
}' "$CONFIG_FILE"

# Add styles for do-not-disturb-indicator
sed -i '/#custom-update {$/{
N
/\n  min-width: 12px;/{
i\
#custom-do-not-disturb-indicator,
}
}' "$STYLE_FILE"

sed -i '/#custom-screenrecording-indicator {$/{
N
/\n  min-width: 12px;/{
i\
#custom-do-not-disturb-indicator,
}
}' "$STYLE_FILE"

echo "waybar configs updated. Backups created at $CONFIG_FILE.bak and $STYLE_FILE.bak"