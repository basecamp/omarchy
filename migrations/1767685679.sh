echo "Add Voxtype to Waybar"

STYLE_FILE=~/.config/waybar/style.css
CONFIG_FILE=~/.config/waybar/config.jsonc

# Add voxtype CSS if not present
if ! grep -q "#custom-voxtype" "$STYLE_FILE"; then
  sed -i 's/margin-left: 8\.75px;/margin-left: 5px;/' "$STYLE_FILE"
  sed -i '/#custom-screenrecording-indicator {/,/}/ s/font-size: 10px;/font-size: 10px;\n  padding-bottom: 1px;/' "$STYLE_FILE"
  cat >> "$STYLE_FILE" << 'EOF'

#custom-voxtype {
  min-width: 12px;
  margin: 0 0 0 7.5px;
}

#custom-voxtype.recording {
  color: #a55555;
}
EOF
fi

# Add voxtype to modules-center if not present
if ! grep -q "custom/voxtype" "$CONFIG_FILE"; then
  # Add to modules-center array
  sed -i 's/"custom\/screenrecording-indicator"]/"custom\/voxtype", "custom\/screenrecording-indicator"]/' "$CONFIG_FILE"

  # Add voxtype config block before tray config
  sed -i '/"tray": {/i\  "custom/voxtype": {\n    "exec": "omarchy-voxtype-status",\n    "return-type": "json",\n    "format": "{icon}",\n    "format-icons": {\n      "idle": "",\n      "recording": "󰍬",\n      "transcribing": "󰔟"\n    },\n    "tooltip": true,\n    "on-click-right": "omarchy-voxtype-config",\n    "on-click": "omarchy-voxtype-model"\n  },' "$CONFIG_FILE"
fi

omarchy-restart-waybar
