echo "Remove opacity from alacritty.toml so Hyprland can control fully"

if [[ -f ~/.config/alacritty/alacritty.toml ]]; then
  sed -i '/opacity = 0.98/d' ~/.config/alacritty/alacritty.toml
fi
