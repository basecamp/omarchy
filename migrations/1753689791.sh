echo "Add the new ristretto theme as an option"

if [[ ! -L ~/.config/omarchy/themes/ristretto ]]; then
  ln -nfs ~/.local/share/omarchy/themes/ristretto ~/.config/omarchy/themes/
fi
