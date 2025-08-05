echo "Add auto-update icon to waybar when update available"

if ! grep -q "custom/update" ~/.config/waybar/config.jsonc; then
  ~/.local/share/omarchy/bin/omarchy-refresh-waybar
fi
