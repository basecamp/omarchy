#!/bin/bash

if omarchy-pkg-aur-accessible; then
  yay -S --noconfirm --needed \
    typora ttf-ia-writer \
    tzupdate wl-screenrec python-terminaltexteffects
else
  echo -e "\n\e[31mAUR is unavailable. Skipping installation of: 1password, Typora, tte, tzupdate !\e[0m"
  echo "You will have to install these later when AUR is available."
  sleep 5
fi
