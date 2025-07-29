#!/bin/bash

yay -S --noconfirm --needed ttf-font-awesome ttf-cascadia-mono-nerd ttf-ia-writer noto-fonts noto-fonts-emoji

if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed noto-fonts-cjk noto-fonts-extra
fi
