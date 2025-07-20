#!/bin/bash

if [ -z "$OMARCHY_BARE" ]; then
  yay -S --noconfirm --needed \
    gnome-calculator gnome-keyring signal-desktop \
    obsidian-bin libreoffice obs-studio kdenlive \
    xournalpp localsend-bin

  yay -S --noconfirm --needed pinta ||
    echo -e "\e[31mFailed to install Pinta. Continuing without!\e[0m"

  yay -S --noconfirm --needed typora ||
    echo -e "\e[31mFailed to install Typora. Continuing without!\e[0m"

  yay -S --noconfirm --needed zoom ||
    echo -e "\e[31mFailed to install Zoom. Continuing without!\e[0m"

  yay -S --noconfirm --needed dropbox libappindicator-gtk3 python-gpgme nautilus-dropbox ||
    echo -e "\e[31mFailed to install Dropbox. Continuing without!\e[0m"

  yay -S --noconfirm --needed spotify ||
    echo -e "\e[31mFailed to install Spotify (likely because of a keyserver problem). Continuing without!\e[0m"

  yay -S --noconfirm --needed 1password-beta 1password-cli ||
    echo -e "\e[31mFailed to install 1password (likely because of a keyserver problem). Continuing without!\e[0m"
fi

# Copy over Omarchy applications
source ~/.local/share/omarchy/bin/omarchy-refresh-applications || true
