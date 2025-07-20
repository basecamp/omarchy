echo "Replace wofi with walker as the default launcher"

if [[ ! -d ~/.config/walker ]]; then
  yay -Sy --noconfirm --needed walker-bin libqalculate

  yay -Rns --noconfirm wofi
  rm -rf ~/.config/wofi

  mkdir -p ~/.config/walker
  cp -r ~/.local/share/omarchy/config/walker/* ~/.config/walker/
fi
