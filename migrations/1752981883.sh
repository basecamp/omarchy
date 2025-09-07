echo "Replace wofi with walker as the default launcher"

if omarchy-cmd-missing walker; then
  omarchy-pkg-add walker-bin libqalculate

  omarchy-pkg-drop wofi
  rm -rf ~/.config/wofi

  mkdir -p ~/.config/walker
  cp -r ~/.local/share/omarchy/config/walker/* ~/.config/walker/
fi
