echo "Install swayOSD to show volume status"

if ! command -v swayosd-server &>/dev/null; then
  sudo pacman -S --noconfirm --needed swayosd
  setsid uwsm app -- swayosd-server &>/dev/null &
fi
