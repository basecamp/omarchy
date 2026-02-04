#!/bin/bash

if [ -z "$AUTARKY_BARE" ]; then
  yay -S --noconfirm --needed \
    gnome-calculator gnome-keyring vesktop-bin \
    obsidian-bin obs-studio kdenlive \
    xournalpp localsend-bin

  # Packages known to be flaky or having key signing issues are run one-by-one
  for pkg in pinta zoom; do
    yay -S --noconfirm --needed "$pkg" ||
      echo -e "\e[31mFailed to install $pkg. Continuing without!\e[0m"
  done

fi

# Copy over Autarky applications
source ~/.local/share/autarky/bin/autarky-refresh-applications || true
