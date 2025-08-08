echo "Update Waybar config to fix path issue with update-available icon click"

if grep -q "alacritty --class Omarchy --title Omarchy -e omarchy-update" ~/.config/waybar/config.jsonc; then
  sed -i 's|\("on-click": "alacritty --class Omarchy --title Omarchy -e \)omarchy-update"|\1~/.local/share/omarchy/bin/omarchy-update"|' ~/.config/waybar/config.jsonc
  ~/.local/share/omarchy/bin/omarchy-restart-waybar
fi
