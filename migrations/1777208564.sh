echo "Add Piper TTS to Waybar"

STYLE_FILE=~/.config/waybar/style.css
CONFIG_FILE=~/.config/waybar/config.jsonc

# Add Piper CSS if not present
if ! grep -q "#custom-piper.reading" "$STYLE_FILE"; then
  cat >>"$STYLE_FILE" <<'EOF'

#custom-piper.reading {
  min-width: 12px;
  margin: 0 0 0 7.5px;
  color: #a55555;
  opacity: 0.6;
  animation: blink 1s steps(2) infinite;
}

@keyframes blink {
  to {
    opacity: 1;
  }
}
EOF
fi

# Add Piper to modules-center if not present
if ! grep -q "custom/piper" "$CONFIG_FILE"; then
  if grep -q '"custom/voxtype", ' "$CONFIG_FILE"; then
    sed -i 's/"custom\/voxtype", /"custom\/voxtype", "custom\/piper", /' "$CONFIG_FILE"
  else
    sed -i '/"modules-center"/ s/"custom\/screenrecording-indicator"/"custom\/piper", "custom\/screenrecording-indicator"/' "$CONFIG_FILE"
  fi

  sed -i '/"tray": {/i\  "custom/piper": {\n    "exec": "omarchy-piper-status",\n    "return-type": "json",\n    "format": "{}",\n    "tooltip": true,\n    "signal": 11\n  },' "$CONFIG_FILE"
fi

omarchy-restart-waybar
