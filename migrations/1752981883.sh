echo "Replace wofi with walker as the default launcher"

if cmd-missing walker; then
  pkg-add walker-bin libqalculate

  pkg-remove wofi
  rm -rf ~/.config/wofi

  mkdir -p ~/.config/walker
  cp -r ~/.local/share/omarchy/config/walker/* ~/.config/walker/
fi
