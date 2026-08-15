echo "Add weather widget to Waybar"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"

if [[ -f $WAYBAR_CONFIG ]]; then
  if ! grep -q '"custom/weather"' "$WAYBAR_CONFIG"; then
    sed -i 's/"modules-center": \["clock",/"modules-center": ["clock", "custom\/weather",/' "$WAYBAR_CONFIG"
    sed -i '/"network": {/i\  "custom/weather": {\n    "exec": "$OMARCHY_PATH/default/waybar/weather.sh",\n    "return-type": "json",\n    "interval": 60,\n    "tooltip": false,\n    "on-click": "notify-send -u low \\"$(omarchy-weather-status)\\""\n  },' "$WAYBAR_CONFIG"
  fi
fi

if [[ -f $WAYBAR_STYLE ]] && ! grep -q '#custom-weather' "$WAYBAR_STYLE"; then
  cat >>"$WAYBAR_STYLE" <<'EOF'

#custom-weather {
  margin-left: 7.5px;
  margin-right: 7.5px;
}

#custom-weather.unavailable {
  min-width: 0;
  margin: 0;
  padding: 0;
}
EOF
fi

omarchy-restart-waybar
