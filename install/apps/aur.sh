#!/bin/bash

if curl -sf --connect-timeout 30 -A "omarchy-update" \
  "https://aur.archlinux.org/rpc/?v=5&type=info&arg=base" |
  jq -e '.type=="multiinfo"' >/dev/null; then
  if [ -z "$OMARCHY_BARE" ]; then
    yay -S --noconfirm --needed \
      1password-beta 1password-cli \
      typora ttf-ia-writer
  fi

  yay -S --noconfirm --needed \
    tzupdate wl-screenrec \
    python-poetry-core python-terminaltexteffects

  # We install chromium to be safe that we have a browser,
  # but replace it with our version if AUR is available
  sudo pacman -Rns chromium
  yay -S --noconfirm omarchy-chromium-bin
else
  echo -e "\n\e[31mAUR is unavailable. Skipping installation of: 1password, Typora, tte, tzupdate !\e[0m"
  echo "You will have to install these later when AUR is available."
  sleep 5
fi
