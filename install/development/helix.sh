#!/bin/bash

if ! command -v helix &>/dev/null; then
  yay -S --noconfirm --needed helix

  # Set Helix config
  rm -rf ~/.config/helix
  git clone https://github.com/LazyVim/starter ~/.config/nvim
  cp -R ~/.local/share/omarchy/config/helix/* ~/.config/helix/
  rm -rf ~/.config/helix/.git
fi
