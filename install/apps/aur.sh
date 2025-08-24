#!/bin/bash

if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed \
    1password-beta 1password-clia \
    python-poetry-core python-terminaltexteffects \
    tzupdate wl-screenrec \
    typora ttf-ia-writer
fi

# We install chromium to be safe that we have a browser,
# but replace it with our version if AUR is available
sudo pacman -Rns chromium
yay -S --noconfirm omarchy-chromium-bin
