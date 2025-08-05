echo "Fixing persistent workspaces in waybar config"

if [[ -f ~/.config/waybar/config ]]; then
  sed -i 's/"persistent_workspaces":/"persistent-workspaces":/' ~/.config/waybar/config
  ~/.local/share/omarchy/bin/omarchy-restart-waybar
fi
