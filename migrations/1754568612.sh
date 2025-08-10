echo "Update Waybar config to fix path issue with update-available icon click"

if grep -q "alacritty --class Omarchy --title Omarchy -e omarchy-update" ~/.config/waybar/config.jsonc; then
  sed -i 's|\("on-click": "alacritty --class Omarchy --title Omarchy -e \)omarchy-update"|\1omarchy-update"|' ~/.config/waybar/config.jsonc
  omarchy-state set restart-waybar-required
fi
