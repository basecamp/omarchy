#!/bin/bash

# Set mirror to single geo setup
echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' |
  sudo tee /etc/pacman.d/mirrorlist >/dev/null
