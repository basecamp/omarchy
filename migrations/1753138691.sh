echo "Install swayOSD to show volume status"

if cmd-missing swayosd-server; then
  pkg-add swayosd
  setsid uwsm app -- swayosd-server &>/dev/null &
fi
