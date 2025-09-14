echo "Make it possible to remove update-available icon with signal in Waybar"

if ! grep -q '"signal": 7' ~/.config/waybar/config.jsonc; then
  sed -i '/"tooltip-format": "Omarchy update available",/a\    "signal": 7,' ~/.config/waybar/config.jsonc
fi
