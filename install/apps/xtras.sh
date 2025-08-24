#!/bin/bash

sudo pacman -S --noconfirm --needed \
  gnome-calculator gnome-keyring signal-desktop \
  obsidian libreoffice obs-studio kdenlive \
  1password-beta 1password-cli \
  xournalpp localsend

# Packages known to be flaky or having key signing issues are run one-by-one
for pkg in spotify pinta; do
  sudo pacman -S --noconfirm --needed "$pkg" ||
    echo -e "\e[31mFailed to install $pkg. Continuing without!\e[0m"
done

# Copy over Omarchy applications
source omarchy-refresh-applications || true
