#!/bin/bash

yay -Sy --noconfirm --needed gum python-terminaltexteffects cage alacritty xorg-xwayland unzip

mkdir -p ~/.local/share/fonts

if ! fc-list | grep -qi "CaskaydiaMono Nerd Font"; then
  cd /tmp
  wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip
  unzip CascadiaMono.zip -d CascadiaFont
  cp CascadiaFont/CaskaydiaMonoNerdFont-Regular.ttf ~/.local/share/fonts
  cp CascadiaFont/CaskaydiaMonoNerdFont-Bold.ttf ~/.local/share/fonts
  cp CascadiaFont/CaskaydiaMonoNerdFont-Italic.ttf ~/.local/share/fonts
  cp CascadiaFont/CaskaydiaMonoNerdFont-BoldItalic.ttf ~/.local/share/fonts
  cp CascadiaFont/CaskaydiaMonoNerdFontPropo-Regular.ttf ~/.local/share/fonts
  cp CascadiaFont/CaskaydiaMonoNerdFontPropo-Bold.ttf ~/.local/share/fonts
  cp CascadiaFont/CaskaydiaMonoNerdFontPropo-Italic.ttf ~/.local/share/fonts
  cp CascadiaFont/CaskaydiaMonoNerdFontPropo-BoldItalic.ttf ~/.local/share/fonts
  rm -rf CascadiaMono.zip CascadiaFont
  fc-cache
  cd -
fi
