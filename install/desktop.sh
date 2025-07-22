#!/bin/bash

# Base packages
PACKAGES="brightnessctl playerctl pamixer wiremix wireplumber \
  fcitx5 fcitx5-gtk fcitx5-qt wl-clip-persist \
  nautilus sushi ffmpegthumbnailer \
  slurp satty \
  mpv evince imv \
  chromium"

# Add screen recorder based on GPU
if [ -n "$(lspci | grep -i 'nvidia')" ]; then
  PACKAGES="$PACKAGES wf-recorder"
else
  PACKAGES="$PACKAGES wl-screenrec"
fi

yay -S --noconfirm --needed $PACKAGES
