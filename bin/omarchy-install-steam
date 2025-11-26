#!/bin/bash

set -e

echo "Now pick dependencies matching your graphics card"
sudo pacman -S steam
setsid gtk-launch steam >/dev/null 2>&1 &
