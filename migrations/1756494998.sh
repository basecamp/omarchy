echo "Remove opacity from alacritty.toml so Hyprland can control fully"

sed -i '/opacity = 0.98/d' ~/.config/alacritty/alacritty.toml
