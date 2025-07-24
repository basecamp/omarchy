#!/bin/bash

yay -S --noconfirm --needed \
  brightnessctl playerctl pamixer wiremix wireplumber bluetui \
  fcitx5 fcitx5-gtk fcitx5-qt wl-clip-persist \
  nautilus sushi ffmpegthumbnailer \
  slurp satty \
  mpv evince imv \
  chromium

# Add screen recorder based on GPU
if lspci | grep -qi 'nvidia'; then
  yay -S --noconfirm --needed wf-recorder
else
  yay -S --noconfirm --needed wl-screenrec
fi
