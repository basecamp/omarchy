echo "Rename waybar config file for syntax highlighting"

if [[ -f ~/.config/waybar/config ]]; then
  mv ~/.config/waybar/config ~/.config/waybar/config.jsonc
fi
