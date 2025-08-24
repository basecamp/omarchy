#!/bin/bash

sudo pacman -S --noconfirm --needed ttf-font-awesome ttf-cascadia-mono-nerd noto-fonts noto-fonts-emoji

mkdir -p ~/.local/share/fonts
cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/
fc-cache

if [ -z "$OMARCHY_BARE" ]; then
  sudo pacman -S --noconfirm --needed ttf-jetbrains-mono noto-fonts-cjk noto-fonts-extra
fi
