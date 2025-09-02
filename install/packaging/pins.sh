#!/bin/bash

# We pin explicit packages that are bad upstream here
pinned_packages=$(omarchy-pkg-pinned)

if [[ -n $pinned_packages ]]; then
  echo -e "\e[32m\nInstall pinned system packages\e[0m"

  for pinned in $pinned_packages; do
    echo "sudo pacman -U --noconfirm $pinned"
    sudo pacman -U --noconfirm $pinned
  done
fi
