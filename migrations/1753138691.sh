echo "Install swayOSD to show volume status"

if ! command -v swayosd &>/dev/null; then
  yay -S --noconfirm --needed swayosd
  uwsm app -- swayosd-server &>/dev/null &
fi
