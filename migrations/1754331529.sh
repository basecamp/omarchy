echo "Update Waybar for new Omarchy menu"

if ! grep -q "" ~/.config/waybar/config.jsonc; then
  ~/.local/share/omarchy/bin/omarchy-refresh-waybar
fi
