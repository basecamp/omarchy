echo "Add notification silencing indicator to Waybar"

STYLE_FILE=~/.config/waybar/style.css
CONFIG_FILE=~/.config/waybar/config.jsonc

# Add notification-silencing-indicator to modules-center if not present
if ! grep -q "custom/notification-silencing-indicator" "$CONFIG_FILE"; then
  sed -i 's/"custom\/idle-indicator"]/"custom\/idle-indicator", "custom\/notification-silencing-indicator"]/' "$CONFIG_FILE"

  sed -i '/"tray": {/i\  "custom/notification-silencing-indicator": {\n    "on-click": "omarchy-toggle-notification-silencing",\n    "exec": "$OMARCHY_PATH/default/waybar/indicators/notification-silencing.sh",\n    "signal": 10,\n    "return-type": "json"\n  },' "$CONFIG_FILE"
fi

# Add notification-silencing-indicator CSS if not present
if ! grep -q "#custom-notification-silencing-indicator" "$STYLE_FILE"; then
  # Add to the shared indicator rule
  sed -i 's/#custom-idle-indicator {/#custom-idle-indicator,\n#custom-notification-silencing-indicator {/' "$STYLE_FILE"

  # Add to the shared active color rule
  sed -i 's/#custom-idle-indicator.active {/#custom-idle-indicator.active,\n#custom-notification-silencing-indicator.active {/' "$STYLE_FILE"
fi

omarchy-restart-waybar
