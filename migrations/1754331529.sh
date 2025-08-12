echo "Update Waybar for new Omarchy menu"

if ! grep -q "" ~/.config/waybar/config.jsonc; then
  omarchy-refresh-waybar
fi
