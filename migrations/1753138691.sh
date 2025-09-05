echo "Install swayOSD to show volume status"

if omarchy-cmd-missing swayosd-server; then
  omarchy-pkg-add swayosd
  setsid uwsm app -- swayosd-server &>/dev/null &
fi
