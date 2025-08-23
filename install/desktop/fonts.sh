#!/bin/bash

yay -S --noconfirm --needed ttf-font-awesome ttf-cascadia-mono-nerd ttf-ia-writer noto-fonts noto-fonts-emoji

cp ~/.local/share/omarchy/config/omarchy.ttf /usr/share/fonts/

if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed ttf-jetbrains-mono noto-fonts-cjk noto-fonts-extra
fi
