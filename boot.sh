#!/bin/bash

ansi_art='                                                   
 ▄▄▄▄▄▄▄▄ ▄▄▄    ▄▄▄ ▄▄▄▄▄▄      ▄▄▄▄
 ▀▀▀▀▀███  ██▄  ▄██  ██▀▀▀▀██   ██▀▀██
     ██▀    ██▄▄██   ██    ██  ██    ██
   ▄██▀      ▀██▀    ███████   ██    ██
  ▄██         ██     ██  ▀██▄  ██    ██
 ███▄▄▄▄▄     ██     ██    ██   ██▄▄██
 ▀▀▀▀▀▀▀▀     ▀▀     ▀▀    ▀▀▀   ▀▀▀▀'

clear
echo -e "\n$ansi_art\n"

sudo pacman -Sy --noconfirm --needed git

ZYRO_REPO="${ZYRO_REPO:-lestex/zyro}"

echo -e "\nCloning Zyro from: https://github.com/${ZYRO_REPO}.git"
rm -rf ~/.local/share/zyro/
git clone "https://github.com/${ZYRO_REPO}.git" ~/.local/share/zyro >/dev/null

# Use custom branch if instructed
if [[ -n "$ZYRO_REF" ]]; then
  echo -e "\eUsing branch: $ZYRO_REF"
  cd ~/.local/share/zyro
  git fetch origin "${ZYRO_REF}" && git checkout "${ZYRO_REF}"
  cd -
fi

echo -e "\nInstallation starting..."
source ~/.local/share/zyro/install.sh
