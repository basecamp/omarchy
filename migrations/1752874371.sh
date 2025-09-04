echo "Add Catppuccin Latte light theme"

if [[ ! -L "~/.config/omarchy/themes/catppuccin-latte" ]]; then
  ln -snf ~/.local/share/omarchy/themes/catppuccin-latte ~/.config/omarchy/themes/
fi
