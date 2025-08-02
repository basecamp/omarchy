#!/bin/bash

if ! command -v asdbctl &>/dev/null; then
  echo "Installing asdbctl from the AUR…"
  yay -S --needed --noconfirm asdbctl
fi

