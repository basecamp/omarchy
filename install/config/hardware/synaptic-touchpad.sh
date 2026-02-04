#!/bin/bash
# Enable Synaptics InterTouch for confirmed touchpads if not already loaded

if ! lsmod | grep -q '^psmouse'; then
    echo "Loading psmouse module for synaptics touchpad..."
    modprobe psmouse synaptics_intertouch=1
else
    echo "psmouse module loaded."
fi
