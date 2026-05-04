echo "Make ethereal available as new theme"

if [[ ! -L ~/.config/omarchy/themes/ethereal ]]; then
  rm -rf ~/.config/omarchy/themes/ethereal
  ln -nfs ~/.local/share/omarchy/themes/ethereal ~/.config/omarchy/themes/
fi
