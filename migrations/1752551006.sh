echo "Make wofi stylesheet user editable"
if [[ -L "$HOME/.config/wofi/style.css" ]]; then
  rm "$HOME/.config/wofi/style.css"
  cp ~/.local/share/omarchy/config/wofi/style.css ~/.config/wofi/
fi
