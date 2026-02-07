# Enable Synaptics InterTouch for confirmed touchpads if not already loaded

if grep -qi synaptics /proc/bus/input/devices \
   && ! lsmod | grep -q '^psmouse'; then
    modprobe psmouse synaptics_intertouch=1
fi