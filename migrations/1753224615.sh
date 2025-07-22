echo "Adding SwayOSD"

if [[ ! -d ~/.config/swayosd ]]; then
  mkdir -p ~/.config/swayosd
  cp -r ~/.local/share/omarchy/config/swayosd/* ~/.config/swayosd/
fi
