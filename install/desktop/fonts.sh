#!/bin/bash

sudo pacman -S --noconfirm --needed \
  ttf-font-awesome ttf-cascadia-mono-nerd ttf-jetbrains-mono \
  noto-fonts noto-fonts-emoji noto-fonts-cjk noto-fonts-extra

mkdir -p ~/.local/share/fonts
cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/
fc-cache
