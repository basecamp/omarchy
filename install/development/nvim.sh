#!/bin/bash

if ! command -v nvim &>/dev/null; then
  yay -S --noconfirm --needed nvim luarocks tree-sitter-cli

  # Install LazyVim
  rm -rf ~/.config/nvim
  git clone https://github.com/LazyVim/starter ~/.config/nvim
  cp -R ~/.local/share/omarchy/config/nvim/* ~/.config/nvim/
  cp ~/.local/share/omarchy/config/lazyvim/init.lua ~/.config/nvim/
  cp ~/.local/share/omarchy/config/lazyvim/lazy.lua ~/.config/nvim/lua/config/
  rm -rf ~/.config/nvim/.git
  echo "vim.opt.relativenumber = false" >>~/.config/nvim/lua/config/options.lua
fi
