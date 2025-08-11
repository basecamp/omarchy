echo "Update Waybar CSS to dim unused workspaces"

if ! grep -q "#workspaces button\.empty" ~/.config/waybar/style.css; then
  ~/.local/share/omarchy/bin/omarchy-refresh-config waybar/style.css
  ~/.local/share/omarchy/bin/omarchy-restart-waybar
fi
