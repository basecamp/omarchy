echo "Add idle lock indicator to Waybar"

STYLE_FILE=~/.config/waybar/style.css
CONFIG_FILE=~/.config/waybar/config.jsonc

# Add idle-indicator to modules-center if not present
if ! grep -q "custom/idle-indicator" "$CONFIG_FILE"; then
  sed -i 's/"custom\/screenrecording-indicator"]/"custom\/screenrecording-indicator", "custom\/idle-indicator"]/' "$CONFIG_FILE"

  sed -i '/"tray": {/i\  "custom/idle-indicator": {\n    "on-click": "omarchy-toggle-idle",\n    "exec": "$OMARCHY_PATH/default/waybar/indicators/idle.sh",\n    "signal": 9,\n    "return-type": "json"\n  },' "$CONFIG_FILE"
fi

# Add idle-indicator CSS if not present
if ! grep -q "#custom-idle-indicator" "$STYLE_FILE"; then
  # Remove screenrecording-indicator from shared margin block and pair it with idle-indicator instead
  sed -i 's/^#custom-screenrecording-indicator,$//' "$STYLE_FILE"

  # Add shared rule for both indicators and idle-indicator active state
  sed -i '/#custom-screenrecording-indicator.active {/i\#custom-screenrecording-indicator,\n#custom-idle-indicator {\n  min-width: 12px;\n  margin-left: 5px;\n  margin-right: 0;\n  font-size: 10px;\n  padding-bottom: 1px;\n}\n' "$STYLE_FILE"

  # Remove the now-duplicated properties from the standalone screenrecording block
  sed -i '/#custom-screenrecording-indicator {/,/^}/ {
    /min-width:/d
    /margin-left:/d
    /font-size:/d
    /padding-bottom:/d
    /^#custom-screenrecording-indicator {/d
    /^}$/d
  }' "$STYLE_FILE"

  cat >> "$STYLE_FILE" << 'EOF'

#custom-idle-indicator.active {
  color: #a55555;
}
EOF
fi
