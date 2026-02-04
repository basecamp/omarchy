#!/bin/bash

if ! command -v nvim &>/dev/null; then
  yay -S --noconfirm --needed neovim tree-sitter-cli colorz

  # Install own vim
  cp -rf ~/.local/share/autarky/config/nvim/* ~/.config/nvim/
fi
