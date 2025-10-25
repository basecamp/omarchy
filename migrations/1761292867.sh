echo "Allow Waybar to remember if it's hidden after a restart"

if ! grep -q "start_hidden" ~/.config/waybar/config.jsonc; then
  omarchy-refresh-waybar
fi
