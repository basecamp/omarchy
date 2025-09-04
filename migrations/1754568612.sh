echo "Update Waybar config to fix path issue with update-available icon click"

if grep -q "ghostty --class Omarchy --title Omarchy -e omarchy-update" ~/.config/waybar/config.jsonc; then
  sed -i 's|\("on-click": "ghostty --class Omarchy --title Omarchy -e \)omarchy-update"|\1omarchy-update"|' ~/.config/waybar/config.jsonc
  omarchy-restart-waybar
fi
