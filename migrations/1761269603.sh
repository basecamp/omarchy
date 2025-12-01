echo "Add right-click terminal action to waybar omarchy menu icon"

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

if [[ -f "$WAYBAR_CONFIG" ]] && ! grep -A5 '"custom/omarchy"' "$WAYBAR_CONFIG" | grep -q '"on-click-right"'; then
  sed -i '/"on-click": "omarchy-menu",/a\    "on-click-right": "omarchy-launch-terminal",' "$WAYBAR_CONFIG"
fi
