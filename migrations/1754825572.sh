echo "Installing plugin manager"

if [[ ! -e ~/.config/hypr/plugins.conf ]]; then
  cp ~/.local/share/omarchy/config/hypr/plugins.conf ~/.config/hypr/plugins.conf
fi
