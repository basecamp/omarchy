# Enable Synaptics InterTouch for confirmed touchpads if not already loaded

if ! lsmod | grep -q '^psmouse'; then
  modprobe psmouse synaptics_intertouch=1
fi
