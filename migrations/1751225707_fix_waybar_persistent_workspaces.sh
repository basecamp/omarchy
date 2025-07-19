echo "Fixing persistent workspaces in waybar config"
sed -i 's/"persistent_workspaces":/"persistent-workspaces":/' ~/.config/waybar/config
pkill waybar
setsid waybar >/dev/null 2>&1 &
