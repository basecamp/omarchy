#!/bin/bash

# Install **asdbctl** (HIDRAW) to control Apple Studio Display brightness.
# Required on Intel + Thunderbolt systems where asdcontrol (HIDDEV) fails.

if [ -z "$OMARCHY_BARE" ] && ! command -v asdbctl &>/dev/null; then
  yay -S --needed --noconfirm asdbctl
fi
