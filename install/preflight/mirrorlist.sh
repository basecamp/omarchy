#!/bin/bash

# Set mirror to single geo setup
echo 'Server = http://mirror.23m.com/archlinux/$repo/os/$arch' |
  sudo tee /etc/pacman.d/mirrorlist >/dev/null

# Update indexes if online
if ping -c5 omarchy.org &>/dev/null; then
  sudo pacman -Syy
fi
