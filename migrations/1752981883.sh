echo "Replace wofi with walker as the default launcher"

if ! command -v walker &>/dev/null; then
  yay -Sy --noconfirm --needed walker-bin libqalculate

  yay -Rn --noconfirm wofi
  rm -rf ~/.config/wofi

  mkdir -p ~/.config/walker
  cp -r ~/.local/share/omarchy/config/walker/* ~/.config/walker/

  uwsm app -- walker --gapplication-service
fi
