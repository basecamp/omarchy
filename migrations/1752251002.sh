echo "Migrate to the modular, variable-based implementation of waybar style.css"

if [ -L ~/.config/waybar/style.css ]; then
  rm ~/.config/waybar/style.css
  cp ~/.local/share/omarchy/config/waybar/style.css ~/.config/waybar/style.css
fi
