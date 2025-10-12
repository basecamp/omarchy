echo "Add the new Flexoki Light theme"

if [[ ! -L ~/.config/omarchy/themes/flexoki-light ]]; then
  ln -nfs ~/.local/share/omarchy/themes/flexoki-light ~/.config/omarchy/themes/
fi
