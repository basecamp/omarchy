#!/bin/bash

yay -S --noconfirm --needed ttf-font-awesome ttf-cascadia-mono-nerd ttf-ia-writer noto-fonts noto-fonts-emoji ttf-firacode-nerd

if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed ttf-jetbrains-mono noto-fonts-cjk noto-fonts-extra
fi
